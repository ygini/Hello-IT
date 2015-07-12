//
//  HITPSubCommand.m
//  SubCommand
//
//  Created by Yoann Gini on 12/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPSubCommand.h"
#include <Security/Security.h>

#define kHITPSubCommandTitle @"title"
#define kHITPSubCommandRepeat @"repeat"
#define kHITPSubCommandScript @"commandPath"
#define kHITPSubCommandArgs @"args"

@interface HITPSubCommand ()
@property NSString *title;
@property NSNumber *repeat;
@property NSString *script;
@property HITPluginTestState testState;
@property NSTimer *cron;
@property NSMenuItem *menuItem;
@property NSInteger timeout;
@property NSString *base64PlistArgs;
@end

@implementation HITPSubCommand

+ (id<HITPluginProtocol>)newPlugInInstanceWithSettings:(NSDictionary*)settings {
    id instance = [[self alloc] initWithSettings:settings];
    return instance;
}

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super init];
    if (self) {
        _title = [settings objectForKey:kHITPSubCommandTitle];
        _repeat = [settings objectForKey:kHITPSubCommandRepeat];
        _script = [settings objectForKey:kHITPSubCommandScript];
        
        NSDictionary *args = [settings objectForKey:kHITPSubCommandArgs];
        if (args) {
            NSError *error = nil;
            NSData *plistArgs = [NSPropertyListSerialization dataWithPropertyList:args
                                                                           format:NSPropertyListXMLFormat_v1_0
                                                                          options:0
                                                                            error:&error];
            // TODO: log error
            

            SecTransformRef transform = SecEncodeTransformCreate(kSecBase64Encoding, NULL);
            
            NSData *base64Data = nil;
            if (SecTransformSetAttribute(transform, kSecTransformInputAttributeName, (__bridge CFTypeRef)(plistArgs), NULL)) {
                base64Data = (NSData *)CFBridgingRelease(SecTransformExecute(transform, NULL));
            }
            
            CFRelease(transform);
            
            _base64PlistArgs = [[NSString alloc] initWithData:base64Data
                                                     encoding:NSASCIIStringEncoding];

        } else {
            _base64PlistArgs = @"";
        }
        
        _menuItem = [[NSMenuItem alloc] initWithTitle:self.title
                                               action:@selector(runTheTest:)
                                        keyEquivalent:@""];
        _menuItem.target = self;
        [_menuItem setState:NSOffState];
        
        if ([_repeat intValue] > 0) {
            _cron = [NSTimer scheduledTimerWithTimeInterval:[_repeat integerValue]
                                                     target:self
                                                   selector:@selector(runTheTest:)
                                                   userInfo:nil
                                                    repeats:YES];
            
            [_cron fire];
        }
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

- (void)runTheTest:(id)sender {
    [self runTheTest];
}

- (void)runTheTest {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        int returnCode = [self runScript];
        switch (returnCode) {
            case 0:
                self.testState = HITPluginTestStateGreen;
                break;
            case 1:
                self.testState = HITPluginTestStateOrange;
                break;
            case 2:
                self.testState = HITPluginTestStateRed;
                break;
            default:
                self.testState = HITPluginTestStateNoState;
                break;
        }
        
        [self updateMenuItemState];
    });
}

- (int)runScript {
    int returnCode = -1;
    [self runScriptReturnCodeNeeded:&returnCode];
    return returnCode;
}

- (NSString*)runScriptReturnCodeNeeded:(int*)returnCode {
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:self.script];
    [task setArguments:@[self.base64PlistArgs]];
    
    [task setStandardOutput:[NSPipe pipe]];
    
    [task launch];
    
    [task waitUntilExit];
    
    if (returnCode) {
        *returnCode = [task terminationStatus];
    }
    
    NSPipe *readingPipe = [task standardOutput];
    
    NSData *data = [[readingPipe fileHandleForReading] readDataToEndOfFile];

    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@end
