//
//  HITPScriptedItem.m
//  ScriptedItem
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPScriptedItem.h"


#define kHITPSubCommandScript @"path"
#define kHITPSubCommandOptions @"options"
#define kHITPSubCommandArgs @"args"
#define kHITPSubCommandNetworkRelated @"network"

#import <asl.h>

@interface HITPScriptedItem ()
@property NSString *script;
@property BOOL scriptChecked;
@property NSString *base64PlistArgs;
@property BOOL isNetworkRelated;
@property BOOL generalNetworkState;
@property NSArray *options;
@end

@implementation HITPScriptedItem

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _script = [[settings objectForKey:kHITPSubCommandScript] stringByExpandingTildeInPath];
        
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "Loading script based plugin with script at path %s", [_script cStringUsingEncoding:NSUTF8StringEncoding]);
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:_script]) {
            _scriptChecked = YES;
        } else {
            _scriptChecked = NO;
            asl_log(NULL, NULL, ASL_LEVEL_ERR, "Target script not accessible %s", [_script cStringUsingEncoding:NSUTF8StringEncoding]);
        }
        
        _options = [settings objectForKey:kHITPSubCommandOptions];
        
        NSDictionary *args = [settings objectForKey:kHITPSubCommandArgs];
        if (args) {
            NSError *error = nil;
            NSData *plistArgs = [NSPropertyListSerialization dataWithPropertyList:args
                                                                           format:NSPropertyListXMLFormat_v1_0
                                                                          options:0
                                                                            error:&error];
            
            if (error) {
                asl_log(NULL, NULL, ASL_LEVEL_ERR, "Unable to convert args to plist %s", [[error description] cStringUsingEncoding:NSUTF8StringEncoding]);
            }
            
            
            SecTransformRef transform = SecEncodeTransformCreate(kSecBase64Encoding, NULL);
            
            NSData *base64Data = nil;
            CFErrorRef cfError = NULL;
            if (SecTransformSetAttribute(transform, kSecTransformInputAttributeName, (__bridge CFTypeRef)(plistArgs), &cfError)) {
                base64Data = (NSData *)CFBridgingRelease(SecTransformExecute(transform, NULL));
            } else {
                asl_log(NULL, NULL, ASL_LEVEL_ERR, "Untable to encode plist to base64 string %s", [[(__bridge NSError*)cfError description] cStringUsingEncoding:NSUTF8StringEncoding]);
                CFRelease(cfError);
            }
			
            CFRelease(transform);
            
            _base64PlistArgs = [[NSString alloc] initWithData:base64Data
                                                     encoding:NSASCIIStringEncoding];
            
            
            self.isNetworkRelated = [[settings objectForKey:kHITPSubCommandNetworkRelated] boolValue];
            
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
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "Start script with command %s", [command cStringUsingEncoding:NSUTF8StringEncoding]);
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            NSTask *task = [[NSTask alloc] init];
            [task setLaunchPath:self.script];
            
            NSMutableArray *finalArgs = [NSMutableArray new];
            
            [finalArgs addObject:command];
            
            if ([self.options count] > 0) {
                [finalArgs addObjectsFromArray:self.options];
                asl_log(NULL, NULL, ASL_LEVEL_DEBUG, "Adding array of option as arguments");
            }
            
            if ([self.base64PlistArgs length] > 0) {
                [finalArgs addObject:self.base64PlistArgs];
                asl_log(NULL, NULL, ASL_LEVEL_DEBUG, "Adding base64 plist encoded as arguments");
            }
            
            if (self.isNetworkRelated) {
                [finalArgs addObject:self.generalNetworkState ? @"1" : @"0"];
                asl_log(NULL, NULL, ASL_LEVEL_DEBUG, "Adding network state as arguments");
            }
            
            [task setArguments:finalArgs];
            
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
            asl_log(NULL, NULL, ASL_LEVEL_INFO, "Script exited with code %i", [task terminationStatus]);
        });
    }
}

- (void)handleScriptRequest:(NSString*)request {
    asl_log(NULL, NULL, ASL_LEVEL_INFO, "Script request recieved: %s", [request cStringUsingEncoding:NSUTF8StringEncoding]);
    
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
            
        } else if ([key isEqualToString:@"hitp-hidden"]) {
            value = [value uppercaseString];
            
            if ([value isEqualToString:@"YES"]) {
                self.menuItem.hidden = YES;
            } else if ([value isEqualToString:@"NO"]) {
                self.menuItem.hidden = NO;
            }
            
        } else if ([key isEqualToString:@"hitp-tooltip"]) {
            self.menuItem.toolTip = value;
            
        } else if ([key isEqualToString:@"hitp-log-emerg"]) {
            asl_log(NULL, NULL, ASL_LEVEL_EMERG, "%s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
            
        } else if ([key isEqualToString:@"hitp-log-alert"]) {
            asl_log(NULL, NULL, ASL_LEVEL_ALERT, "%s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
            
        } else if ([key isEqualToString:@"hitp-log-crit"]) {
            asl_log(NULL, NULL, ASL_LEVEL_CRIT, "%s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
            
        } else if ([key isEqualToString:@"hitp-log-err"]) {
            asl_log(NULL, NULL, ASL_LEVEL_ERR, "%s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
            
        } else if ([key isEqualToString:@"hitp-log-warning"]) {
            asl_log(NULL, NULL, ASL_LEVEL_WARNING, "%s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
            
        } else if ([key isEqualToString:@"hitp-log-notice"]) {
            asl_log(NULL, NULL, ASL_LEVEL_NOTICE, "%s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
            
        } else if ([key isEqualToString:@"hitp-log-info"]) {
            asl_log(NULL, NULL, ASL_LEVEL_INFO, "%s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
            
        } else if ([key isEqualToString:@"hitp-log-debug"]) {
            asl_log(NULL, NULL, ASL_LEVEL_DEBUG, "%s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    });
}

-(void)generalNetworkStateUpdate:(BOOL)state {
    self.generalNetworkState = state;
    [self mainAction:self];
}

@end
