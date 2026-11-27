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
// Do not name this scriptChecked — that shadows HITSimplePlugin’s computedTitle
// flag and makes prepareNewMenuItem call setLaunchPath:nil (SIGABRT on Apply).
@property BOOL commandChecked;
@property NSArray *programArguments;
@property BOOL notifyOnCompletion;
@property id notificationOnCompletion;
@property id<HITPluginsManagerProtocol> pluginsManager;
@end

#define kHITPProgramArguments @"programArguments"
#define kHITPDenyUserWritableScript @"denyUserWritableScript"
#define kHITPNotifyOnCompletion @"notifyOnCompletion"
#define kHITPNotificationOnCompletion @"notificationOnCompletion"

@implementation HITPCommand

/// Resolve a bare command name (e.g. "touch") via PATH to an absolute executable.
- (NSString *)resolvedLaunchPathForCommand:(NSString *)command {
    if (command.length == 0) {
        return nil;
    }
    NSString *expanded = [command stringByExpandingTildeInPath];
    if ([expanded hasPrefix:@"/"]) {
        // Match PATH lookup: missing/non-executable absolute paths must not
        // become commandChecked=YES (isWritableFileAtPath is NO for missing files).
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:expanded]) {
            return expanded;
        }
        return nil;
    }
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    NSString *pathEnv = env[@"PATH"] ?: @"/usr/bin:/bin:/usr/sbin:/sbin";
    for (NSString *dir in [pathEnv componentsSeparatedByString:@":"]) {
        if (dir.length == 0) {
            continue;
        }
        NSString *candidate = [dir stringByAppendingPathComponent:expanded];
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }
    // Common location even if PATH is minimal (GUI apps often have a short PATH).
    for (NSString *dir in @[@"/usr/bin", @"/bin", @"/usr/sbin", @"/sbin"]) {
        NSString *candidate = [dir stringByAppendingPathComponent:expanded];
        if ([[NSFileManager defaultManager] isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }
    return nil;
}

- (void)sendCompletionNotificationLaunched:(BOOL)launched exitStatus:(int)exitStatus {
    if (!self.pluginsManager) {
        os_log_error(OS_LOG_DEFAULT, "Cannot notify on completion: pluginsManager missing");
        return;
    }

    NSString *message = [self localizedString:self.notificationOnCompletion];
    if (message.length == 0) {
        if (!launched) {
            message = @"Failed to run";
        } else if (exitStatus == 0) {
            message = @"Completed successfully";
        } else {
            message = [NSString stringWithFormat:@"Finished with exit code %d", exitStatus];
        }
    }

    NSString *title = [self localizedString:[self.settings objectForKey:kHITSimplePluginTitleKey]];
    if (title.length == 0) {
        title = @"Hello IT";
    }

    [self.pluginsManager sendNotificationWithTitle:title andMessage:message from:self];
}

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _programArguments = [settings objectForKey:kHITPProgramArguments];
        _notificationOnCompletion = [settings objectForKey:kHITPNotificationOnCompletion];
        // Explicit bool, or a non-empty custom message, enables the banner.
        _notifyOnCompletion = [[settings objectForKey:kHITPNotifyOnCompletion] boolValue]
            || ([[self localizedString:_notificationOnCompletion] length] > 0);

        os_log_info(OS_LOG_DEFAULT, "Loading command plugin with program arguments %s", [[_programArguments description] cStringUsingEncoding:NSUTF8StringEncoding]);
        
        if ([_programArguments count] > 0) {
            NSString *command = [_programArguments firstObject];
            NSString *resolved = [self resolvedLaunchPathForCommand:command];
            if (resolved.length > 0) {
                if ([[NSFileManager defaultManager] isWritableFileAtPath:resolved] && [[NSUserDefaults standardUserDefaults] boolForKey:kHITPDenyUserWritableScript]) {
#ifdef DEBUG
                    _commandChecked = YES;
#else
                    _commandChecked = NO;
#endif
                    os_log_error(OS_LOG_DEFAULT, "Target command is writable, security restriction deny such a scenario %s", [resolved cStringUsingEncoding:NSUTF8StringEncoding]);
                } else {
                    _commandChecked = YES;
                    if (![resolved isEqualToString:command]) {
                        os_log_info(OS_LOG_DEFAULT, "Resolved command %s → %s", [command cStringUsingEncoding:NSUTF8StringEncoding], [resolved cStringUsingEncoding:NSUTF8StringEncoding]);
                    }
                }
            } else {
                _commandChecked = NO;
                os_log_error(OS_LOG_DEFAULT, "Target command not accessible %s (need absolute path or a name on PATH, e.g. /usr/bin/touch)", [command cStringUsingEncoding:NSUTF8StringEncoding]);
            }
        } else {
            _commandChecked = NO;
            os_log_error(OS_LOG_DEFAULT, "No valid value for %s", [kHITPProgramArguments cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
    return self;
}

-(void)mainAction:(id)sender {
    if (self.commandChecked && self.allowedToRun) {
        NSMutableArray *arguments = [self.programArguments mutableCopy];
        [arguments removeObjectAtIndex:0];
        
        NSString *command = [self resolvedLaunchPathForCommand:[self.programArguments firstObject]];
        if (command.length == 0) {
            os_log_error(OS_LOG_DEFAULT, "Command no longer resolvable at click time");
            return;
        }
        
        os_log_info(OS_LOG_DEFAULT, "Will run command %s", [command cStringUsingEncoding:NSUTF8StringEncoding]);
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (!self.allowedToRun) {
                return;
            }
            NSTask *task = [[NSTask alloc] init];
            [task setLaunchPath:command];
            [task setArguments:arguments];
                        
            @try {
                [task launch];
                [task waitUntilExit];
                int status = [task terminationStatus];
                os_log_info(OS_LOG_DEFAULT, "Command exited with code %i", status);
                if (self.notifyOnCompletion) {
                    [self sendCompletionNotificationLaunched:YES exitStatus:status];
                }
            } @catch (NSException *exception) {
                os_log_error(OS_LOG_DEFAULT, "Command failed to run: %s", [[exception reason] UTF8String]);
                if (self.notifyOnCompletion) {
                    [self sendCompletionNotificationLaunched:NO exitStatus:-1];
                }
            }
        }];
    }

}


@end
