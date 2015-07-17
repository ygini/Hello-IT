//
//  HITPScriptedItem.m
//  ScriptedItem
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPScriptedItem.h"


#define kHITPSubCommandRepeat @"repeat"
#define kHITPSubCommandScript @"commandPath"
#define kHITPSubCommandArgs @"args"

@interface HITPScriptedItem ()
@property NSMenuItem *menuItem;
@property HITPluginTestState testState;
@property NSTimer *cron;

@property NSNumber *repeat;
@property NSString *script;

@property NSString *base64PlistArgs;
@end

@implementation HITPScriptedItem

+ (id<HITPluginProtocol>)newPlugInInstanceWithSettings:(NSDictionary*)settings {
    id instance = [[self alloc] initWithSettings:settings];
    return instance;
}

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super init];
    if (self) {
        _repeat = [settings objectForKey:kHITPSubCommandRepeat];
        _script = [[settings objectForKey:kHITPSubCommandScript] stringByExpandingTildeInPath];
        
        NSDictionary *args = [settings objectForKey:kHITPSubCommandArgs];
        if (args) {
            NSError *error = nil;
            NSData *plistArgs = [NSPropertyListSerialization dataWithPropertyList:args
                                                                           format:NSPropertyListXMLFormat_v1_0
                                                                          options:0
                                                                            error:&error];
            
            if (error) {
                NSLog(@"Unable to convert args to plist\nError %@", [error localizedDescription]);
            }
            
            
            SecTransformRef transform = SecEncodeTransformCreate(kSecBase64Encoding, NULL);
            
            NSData *base64Data = nil;
            CFErrorRef cfError = NULL;
            if (SecTransformSetAttribute(transform, kSecTransformInputAttributeName, (__bridge CFTypeRef)(plistArgs), &cfError)) {
                base64Data = (NSData *)CFBridgingRelease(SecTransformExecute(transform, NULL));
            } else {
                NSLog(@"Untable to encode plist to base64 string\nError %@", [(__bridge NSError*)cfError localizedDescription]);
                CFRelease(cfError);
            }
            
            CFRelease(transform);
            
            _base64PlistArgs = [[NSString alloc] initWithData:base64Data
                                                     encoding:NSASCIIStringEncoding];
            
        } else {
            _base64PlistArgs = @"";
        }
        
        _menuItem = [[NSMenuItem alloc] initWithTitle:@"…"
                                               action:@selector(runOnce:)
                                        keyEquivalent:@""];
        _menuItem.target = self;
        [_menuItem setState:NSOffState];
        
        if ([_repeat intValue] > 0) {
            _cron = [NSTimer scheduledTimerWithTimeInterval:[_repeat integerValue]
                                                     target:self
                                                   selector:@selector(periodicRun:)
                                                   userInfo:nil
                                                    repeats:YES];
            
            [_cron fire];
        }
        
        [self updateTitle:self];
    }
    return self;
}

- (void)updateMenuItemState {
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (self.testState) {
            case HITPluginTestStateRed:
                self.menuItem.state = NSOffState;
                break;
            case HITPluginTestStateGreen:
                self.menuItem.state = NSOnState;
                break;
            case HITPluginTestStateOrange:
            default:
                self.menuItem.state = NSMixedState;
                break;
        }
    });
}

- (void)runOnce:(id)sender {
    [self runScriptWithCommand:@"run"];
}

- (void)periodicRun:(id)sender {
    [self runScriptWithCommand:@"periodic-run"];
}

- (void)updateTitle:(id)sender {
    [self runScriptWithCommand:@"title"];
}

- (void)runScriptWithCommand:(NSString*)command {
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:self.script];
    [task setArguments:@[command, self.base64PlistArgs]];
    
    [task setStandardOutput:[NSPipe pipe]];
    NSFileHandle *fileToRead = [[task standardOutput] fileHandleForReading];
    
    dispatch_io_t stdoutChannel = dispatch_io_create(DISPATCH_IO_STREAM, [fileToRead fileDescriptor], dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^(int error) {
        
    });
    
    dispatch_io_read(stdoutChannel, 0, SIZE_MAX, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^(bool done, dispatch_data_t data, int error) {
        NSData *stdoutData = (NSData *)data;
        
        NSString *stdoutString = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding];
        
        NSArray *stdoutLines = [stdoutString componentsSeparatedByString:@"\n"];
        
        for (NSString *line in stdoutLines) {
            if ([line hasPrefix:@"hitp-"]) {
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                    [self handleScriptRequest:line];
                });
            }
        }
    });
    
    [task launch];
    
    [task waitUntilExit];
}

- (void)handleScriptRequest:(NSString*)request {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSRange limiterRange = [request rangeOfString:@":"];
        NSString *key = [[[request substringToIndex:limiterRange.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
        NSString *value = [[request substringFromIndex:limiterRange.location+1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if ([key isEqualToString:@"hitp-title"]) {
            self.menuItem.title = value;
            
        } else if ([key isEqualToString:@"hitp-state"]) {
            value = [value lowercaseString];
            
            if ([value isEqualToString:@"green"]) {
                self.testState = HITPluginTestStateGreen;
            } else if ([value isEqualToString:@"orange"]) {
                self.testState = HITPluginTestStateOrange;
            } else if ([value isEqualToString:@"red"]) {
                self.testState = HITPluginTestStateRed;
            } else if ([value isEqualToString:@"none"]) {
                self.testState = HITPluginTestStateNoState;
            }
            
            [self updateMenuItemState];
        } else if ([key isEqualToString:@"hitp-enabled"]) {
            value = [value uppercaseString];
            
            if ([value isEqualToString:@"YES"]) {
                self.menuItem.enabled = YES;
            } else if ([value isEqualToString:@"NO"]) {
                self.menuItem.enabled = NO;
            }
        }
    });
}

@end
