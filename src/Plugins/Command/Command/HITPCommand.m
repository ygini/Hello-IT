//
//  HITPCommand.m
//  Command
//
//  Created by Yoann Gini on 29/10/2019.
//  Copyright © 2019 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPCommand.h"

#import <asl.h>


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
        
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "Loading command plugin with program arguments %s", [[_programArguments description] cStringUsingEncoding:NSUTF8StringEncoding]);
        
        if ([_programArguments count] > 0) {
            NSString * command = [_programArguments firstObject];
            if ([[NSFileManager defaultManager] fileExistsAtPath:command]) {
                if ([[NSFileManager defaultManager] isWritableFileAtPath:command] && [[NSUserDefaults standardUserDefaults] boolForKey:kHITPDenyUserWritableScript]) {
#ifdef DEBUG
                    _scriptChecked = YES;
#else
                    _scriptChecked = NO;
#endif
                    asl_log(NULL, NULL, ASL_LEVEL_ERR, "Target command is writable, security restriction deny such a scenario %s", [command cStringUsingEncoding:NSUTF8StringEncoding]);
                } else {
                    _scriptChecked = YES;
                }
            } else {
                _scriptChecked = NO;
                asl_log(NULL, NULL, ASL_LEVEL_ERR, "Target command not accessible %s", [command cStringUsingEncoding:NSUTF8StringEncoding]);
            }
        } else {
            _scriptChecked = NO;
            asl_log(NULL, NULL, ASL_LEVEL_ERR, "No valid value for %s", [kHITPProgramArguments cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
    return self;
}

-(void)mainAction:(id)sender {
    if (self.scriptChecked && self.allowedToRun) {
        NSMutableArray *arguments = [self.programArguments mutableCopy];
        [arguments removeObjectAtIndex:0];
        
        NSString *command = [self.programArguments firstObject];
        
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "Will run command %s", [command cStringUsingEncoding:NSUTF8StringEncoding]);
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            NSTask *task = [[NSTask alloc] init];
            [task setLaunchPath:command];
            [task setArguments:arguments];
                        
            @try {
                [task launch];
                [task waitUntilExit];
                asl_log(NULL, NULL, ASL_LEVEL_INFO, "Command exited with code %i", [task terminationStatus]);
            } @catch (NSException *exception) {
                asl_log(NULL, NULL, ASL_LEVEL_ERR, "Command failed to run: %s", [[exception reason] UTF8String]);
            }
        }];
    }

}


@end
