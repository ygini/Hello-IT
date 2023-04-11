//
//  HITPCommand.m
//  Command
//
//  Created by Yoann Gini on 29/10/2019.
//  Copyright © 2019 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPCommand.h"

#import <os/log.h>


@interface HITPCommand ()
@property BOOL scriptChecked;
@property NSArray *programArguments;
@end

#define kHITPProgramArguments @"programArguments"
#define kHITPDenyUserWritableScript @"denyUserWritableScript"

@implementation HITPCommand

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _programArguments = [settings objectForKey:kHITPProgramArguments];
        
        os_log_info(OS_LOG_DEFAULT, "Loading command plugin with program arguments %s", [[_programArguments description] cStringUsingEncoding:NSUTF8StringEncoding]);
        
        if ([_programArguments count] > 0) {
            NSString * command = [_programArguments firstObject];
            if ([[NSFileManager defaultManager] fileExistsAtPath:command]) {
                if ([[NSFileManager defaultManager] isWritableFileAtPath:command] && [[NSUserDefaults standardUserDefaults] boolForKey:kHITPDenyUserWritableScript]) {
#ifdef DEBUG
                    _scriptChecked = YES;
#else
                    _scriptChecked = NO;
#endif
                    os_log_error(OS_LOG_DEFAULT, "Target command is writable, security restriction deny such a scenario %s", [command cStringUsingEncoding:NSUTF8StringEncoding]);
                } else {
                    _scriptChecked = YES;
                }
            } else {
                _scriptChecked = NO;
                os_log_error(OS_LOG_DEFAULT, "Target command not accessible %s", [command cStringUsingEncoding:NSUTF8StringEncoding]);
            }
        } else {
            _scriptChecked = NO;
            os_log_error(OS_LOG_DEFAULT, "No valid value for %s", [kHITPProgramArguments cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
    return self;
}

-(void)mainAction:(id)sender {
    if (self.scriptChecked && self.allowedToRun) {
        NSMutableArray *arguments = [self.programArguments mutableCopy];
        [arguments removeObjectAtIndex:0];
        
        NSString *command = [self.programArguments firstObject];
        
        os_log_info(OS_LOG_DEFAULT, "Will run command %s", [command cStringUsingEncoding:NSUTF8StringEncoding]);
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            NSTask *task = [[NSTask alloc] init];
            [task setLaunchPath:command];
            [task setArguments:arguments];
                        
            @try {
                [task launch];
                [task waitUntilExit];
                os_log_info(OS_LOG_DEFAULT, "Command exited with code %i", [task terminationStatus]);
            } @catch (NSException *exception) {
                os_log_error(OS_LOG_DEFAULT, "Command failed to run: %s", [[exception reason] UTF8String]);
            }
        }];
    }

}


@end
