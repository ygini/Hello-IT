//
//  HITPScriptedItem.m
//  ScriptedItem
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPScriptedItem.h"


#define kHITPSubCommandScript @"path"
#define kHITPSubCommandArgs @"args"

@interface HITPScriptedItem ()
@property NSString *script;
@property BOOL scriptChecked;
@property NSString *base64PlistArgs;
@end

@implementation HITPScriptedItem


- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _script = [[settings objectForKey:kHITPSubCommandScript] stringByExpandingTildeInPath];
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:_script]) {
            _scriptChecked = YES;
        } else {
            _scriptChecked = NO;
            NSLog(@"Target script no accessible (%@)", _script);
        }
        
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
        
    }
    return self;
}

-(NSMenuItem *)prepareNewMenuItem {
    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:@"…"
                                           action:@selector(mainAction:)
                                    keyEquivalent:@""];
    menuItem.target = self;
    
    [self performSelector:@selector(updateTitle) withObject:nil afterDelay:0];
    
    return menuItem;
}

-(void)mainAction:(id)sender {
    [self runScriptWithCommand:@"run"];
}

-(void)periodicAction:(NSTimer *)timer {
    [self runScriptWithCommand:@"periodic-run"];
}

- (void)updateTitle {
    [self runScriptWithCommand:@"title"];
}

- (void)runScriptWithCommand:(NSString*)command {
    if (self.scriptChecked) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
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
        });
    }
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
            
            if ([value isEqualToString:@"ok"]) {
                self.testState = HITPluginTestStateOK;
            } else if ([value isEqualToString:@"warning"]) {
                self.testState = HITPluginTestStateWarning;
            } else if ([value isEqualToString:@"error"]) {
                self.testState = HITPluginTestStateError;
            } else if ([value isEqualToString:@"none"]) {
                self.testState = HITPluginTestStateNone;
            } else if ([value isEqualToString:@"unavailable"]) {
                self.testState = HITPluginTestStateUnavailable;
            }
            
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
