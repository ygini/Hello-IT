//
//  HITPOpenApplication.m
//  OpenApplication
//
//  Created by Yoann Gini on 16/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPOpenApplication.h"

#define kHITPOpenApplicationName @"app"
#define kHITPOpenApplicationFileToOpen @"file"

#define kHITPOpenApplicationURL @"appURL"
#define kHITPOpenApplicationArgsArray @"args"

#define kHITPOpenApplicationHideIfNotAvailable @"hideIfNotAvailable"

#import <os/log.h>

@interface HITPOpenApplication ()
@property NSString *application;
@property NSString *file;

@property NSURL *appURL;
@property NSArray *args;

@property BOOL hideIfNotAvailable;

@end

@implementation HITPOpenApplication

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _application = [settings objectForKey:kHITPOpenApplicationName];
        _file = [[settings objectForKey:kHITPOpenApplicationFileToOpen] stringByExpandingTildeInPath];
        _hideIfNotAvailable = [[settings objectForKey:kHITPOpenApplicationHideIfNotAvailable] boolValue];
        
        NSString *appPath = [settings objectForKey:kHITPOpenApplicationURL];
        if (appPath) {
            _appURL = [NSURL fileURLWithPath:appPath];
            _args = [settings objectForKey:kHITPOpenApplicationArgsArray];
            
            if (!_args) {
                _args = @[];
            }
        }
        
        [self hideItemIfNeeded];
    }
    return self;
}

- (void)hideItemIfNeeded {
    if (self.hideIfNotAvailable) {
        if (self.application) {
            self.menuItem.hidden = [[NSWorkspace sharedWorkspace] fullPathForApplication:self.application] == nil;
            if (self.menuItem.hidden) {
                os_log_info(OS_LOG_DEFAULT, "Menu item %s for %s is hidden, workspace unable to find requested app.", [self.menuItem.title cStringUsingEncoding:NSUTF8StringEncoding], [self.application cStringUsingEncoding:NSUTF8StringEncoding]);
            }
        } else {
            self.menuItem.hidden = ![[NSFileManager defaultManager] fileExistsAtPath:[self.appURL path]];
            if (self.menuItem.hidden) {
                os_log_info(OS_LOG_DEFAULT, "Menu item %s for app at path %s is hidden, path does not exist.", [self.menuItem.title cStringUsingEncoding:NSUTF8StringEncoding], [[self.appURL path] cStringUsingEncoding:NSUTF8StringEncoding]);
            }
        }
    } else {
        self.menuItem.hidden = NO;
    }
}

- (void)mainAction:(id)sender {
    if (self.application) {
        os_log_info(OS_LOG_DEFAULT, "User requested to open %s with optional file %s.", [self.application cStringUsingEncoding:NSUTF8StringEncoding], [self.file cStringUsingEncoding:NSUTF8StringEncoding]);
        [[NSWorkspace sharedWorkspace] openFile:self.file withApplication:self.application andDeactivate:YES];
    } else if (self.appURL) {
        os_log_info(OS_LOG_DEFAULT, "User requested to open application at path %s with opional args %s.", [[self.appURL absoluteString] cStringUsingEncoding:NSUTF8StringEncoding], [[self.args description] cStringUsingEncoding:NSUTF8StringEncoding]);
        NSError *error = nil;
        [[NSWorkspace sharedWorkspace] launchApplicationAtURL:self.appURL options:0 configuration:@{NSWorkspaceLaunchConfigurationArguments: self.args} error:&error];
        
        if (error) {
            os_log_error(OS_LOG_DEFAULT, "Error when running app:\n%s", [[error description] cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
}

@end
