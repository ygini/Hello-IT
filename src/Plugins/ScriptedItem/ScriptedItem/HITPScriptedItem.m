//
//  HITPScriptedItem.m
//  ScriptedItem
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPScriptedItem.h"


#define kHITPSubCommandScriptPath @"path"
#define kHITPSubCommandScriptName @"script"
#define kHITPSubCommandOptions @"options"
#define kHITPSubCommandArgs @"args"
#define kHITPSubCommandNetworkRelated @"network"
#define kHITSimplePluginTitleKey @"title"
#define kHITPDenyUserWritableScript @"denyUserWritableScript"

#define kHITPCustomScriptsPath @"/Library/Application Support/com.github.ygini.hello-it/CustomScripts"

//#ifdef DEBUG
//#warning This static path to the development custom scripts must be replaced by something smart
//#define kHITPCustomScriptsPath @"/Users/ygi/Sources/Public/Hello-IT/src/Plugins/ScriptedItem/CustomScripts"
//#endif

#import <os/log.h>

@interface HITPScriptedItem ()
@property NSString *script;
@property BOOL scriptChecked;
@property BOOL network;
@property BOOL generalNetworkState;
@property NSArray *options;
@end

@implementation HITPScriptedItem

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _network = [[settings objectForKey:kHITPSubCommandNetworkRelated] boolValue];
        _script = [[settings objectForKey:kHITPSubCommandScriptPath] stringByExpandingTildeInPath];
        
        if ([_script length] == 0) {
            _script = [[NSString stringWithFormat:kHITPCustomScriptsPath] stringByAppendingPathComponent:[settings objectForKey:kHITPSubCommandScriptName]];
        }
        
        os_log_info(OS_LOG_DEFAULT, "Loading script based plugin with script at path %s", [_script cStringUsingEncoding:NSUTF8StringEncoding]);
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:_script]) {
            if ([[NSFileManager defaultManager] isWritableFileAtPath:_script] && [[NSUserDefaults standardUserDefaults] boolForKey:kHITPDenyUserWritableScript]) {
#ifdef DEBUG
                _scriptChecked = YES;
#else
                _scriptChecked = NO;
#endif
                os_log_error(OS_LOG_DEFAULT, "Target script is writable, security restriction deny such a scenario %s", [_script cStringUsingEncoding:NSUTF8StringEncoding]);
            } else {
                _scriptChecked = YES;
            }
        } else {
            _scriptChecked = NO;
            os_log_error(OS_LOG_DEFAULT, "Target script not accessible %s", [_script cStringUsingEncoding:NSUTF8StringEncoding]);
        }
        
        _options = [settings objectForKey:kHITPSubCommandOptions];
        
        NSDictionary *args = [settings objectForKey:kHITPSubCommandArgs];
        if (args) {
            os_log_error(OS_LOG_DEFAULT, "Args options to be sent in base64 format isn't supported anymore by scripted items. Use options instead");
        }
        
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p, script:%@, checked:%@, network: %@>", self.className, self, self.script, self.scriptChecked ? @"YES" : @"NO", self.network ? @"YES" : @"NO"];
}

- (BOOL)isNetworkRelated {
    return self.network;
}

-(NSMenuItem *)prepareNewMenuItem {
    NSString *title = [self localizedString:[self.settings objectForKey:kHITSimplePluginTitleKey]];
    if (!title) {
        title = @"Title error";
    }
    
    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:title
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

-(void)generalNetworkStateUpdate:(BOOL)state {
    self.generalNetworkState = state;
    if (self.isNetworkRelated) {
        [self runScriptWithCommand:@"network"];
    }
}

- (void)runScriptWithCommand:(NSString*)command {
    if (self.scriptChecked && self.allowedToRun) {
        os_log_info(OS_LOG_DEFAULT, "Start script %s with command %s", [self.script.lastPathComponent cStringUsingEncoding:NSUTF8StringEncoding], [command cStringUsingEncoding:NSUTF8StringEncoding]);
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            NSTask *task = [[NSTask alloc] init];
            [task setLaunchPath:self.script];
            
            NSMutableDictionary *environment = [NSMutableDictionary dictionaryWithDictionary:[[NSProcessInfo processInfo] environment]];
            
            [environment setObject:kHITPCustomScriptsPath
                            forKey:@"HELLO_IT_SCRIPT_FOLDER"];
            
            [environment setObject:[[[NSBundle bundleForClass:[self class]] resourcePath] stringByAppendingPathComponent:@"scriptLibraries/bash"]
                            forKey:@"HELLO_IT_SCRIPT_SH_LIBRARY"];
            
            NSMutableArray *finalArgs = [NSMutableArray new];
            
            [finalArgs addObject:command];
            
            if ([self.options count] > 0) {
                os_log_debug(OS_LOG_DEFAULT, "Adding array of option as arguments");
                [finalArgs addObjectsFromArray:self.options];
                
                [environment setObject:@"yes"
                                forKey:@"HELLO_IT_OPTIONS_AVAILABLE"];
                
                NSMutableString *args = [NSMutableString new];
                
                for (NSString *arg in self.options) {
                    [args appendString:arg];
                    [args appendString:@" "];
                }
                
                [environment setObject:args
                                forKey:@"HELLO_IT_OPTIONS"];
            } else {
                [environment setObject:@"no"
                                forKey:@"HELLO_IT_OPTIONS_AVAILABLE"];
            }
            
            [environment setObject:self.generalNetworkState ? @"yes" : @"no"
                            forKey:@"HELLO_IT_NETWORK_TEST"];
            
            [task setEnvironment:environment];
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
            
            @try {
                [task launch];
                
                [task waitUntilExit];
                
                os_log_info(OS_LOG_DEFAULT, "Script %s exited with code %i", [self.script.lastPathComponent cStringUsingEncoding:NSUTF8StringEncoding], [task terminationStatus]);
            } @catch (NSException *exception) {
                os_log_error(OS_LOG_DEFAULT, "Script %s failed to run: %s", [self.script.lastPathComponent cStringUsingEncoding:NSUTF8StringEncoding], [[exception reason] UTF8String]);
            }
        });
    }
}

- (void)handleScriptRequest:(NSString*)request {
    os_log_info(OS_LOG_DEFAULT, "Script request recieved: %s", [request cStringUsingEncoding:NSUTF8StringEncoding]);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        NSRange limiterRange = [request rangeOfString:@":"];
        NSString *key = [[[request substringToIndex:limiterRange.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] lowercaseString];
        NSString *value = [[request substringFromIndex:limiterRange.location+1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        value = [value stringByReplacingOccurrencesOfString:@"\\n" withString:@"\n"];
        
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
            
        } else if ([key isEqualToString:@"hitp-checked"]) {
            value = [value uppercaseString];
            
            if ([value isEqualToString:@"YES"]) {
                self.menuItem.state = NSOnState;
            } else if ([value isEqualToString:@"NO"]) {
                self.menuItem.state = NSOffState;
            } else if ([value isEqualToString:@"MIXED"]) {
                self.menuItem.state = NSMixedState;
            }
            
        } else if ([key isEqualToString:@"hitp-hidden"]) {
            value = [value uppercaseString];
            
            if ([value isEqualToString:@"YES"]) {
                self.menuItem.hidden = YES;
            } else if ([value isEqualToString:@"NO"]) {
                self.menuItem.hidden = NO;
            }
            
        } else if ([key isEqualToString:@"hitp-open"]) {
            NSURL * valueURL = [NSURL URLWithString:value];
            
            if (valueURL) {
                [[NSWorkspace sharedWorkspace] openURL:valueURL];
            } else {
                os_log_info(OS_LOG_DEFAULT, "Unable to decode this as an URL conforms to RFCs 2396, 1738 and 1808.: %s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
            }
            
        } else if ([key isEqualToString:@"hitp-notification"]) {
            [self sendNotificationWithMessage:value];
            
        } else if ([key isEqualToString:@"hitp-tooltip"]) {
            self.menuItem.toolTip = value;
            
        } else if ([key isEqualToString:@"hitp-log-emerg"]) {
            os_log_fault(OS_LOG_DEFAULT, "hitp-log-emerg: %s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
            
        } else if ([key isEqualToString:@"hitp-log-alert"]) {
            os_log_fault(OS_LOG_DEFAULT, "hitp-log-alert: %s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
            
        } else if ([key isEqualToString:@"hitp-log-crit"]) {
            os_log_error(OS_LOG_DEFAULT, "hitp-log-crit: %s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
            
        } else if ([key isEqualToString:@"hitp-log-err"]) {
            os_log_error(OS_LOG_DEFAULT, "hitp-log-err: %s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
            
        } else if ([key isEqualToString:@"hitp-log-warning"]) {
            os_log_info(OS_LOG_DEFAULT, "hitp-log-warning: %s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
            
        } else if ([key isEqualToString:@"hitp-log-notice"]) {
            os_log_info(OS_LOG_DEFAULT, "hitp-log-notice: %s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
            
        } else if ([key isEqualToString:@"hitp-log-info"]) {
            os_log_info(OS_LOG_DEFAULT, "hitp-log-info: %s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
            
        } else if ([key isEqualToString:@"hitp-log-debug"]) {
            os_log_debug(OS_LOG_DEFAULT, "hitp-log-debug: %s", [value cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    });
}

- (void)actionFromNotification:(NSUserNotification *)notification {
    [self runScriptWithCommand:@"notification"];
}

@end
