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

#import <asl.h>

@interface HITPOpenApplication ()
@property NSString *application;
@property NSString *file;

@property NSURL *appURL;
@property NSArray *args;
@end

@implementation HITPOpenApplication

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _application = [settings objectForKey:kHITPOpenApplicationName];
        _file = [[settings objectForKey:kHITPOpenApplicationFileToOpen] stringByExpandingTildeInPath];
        
        NSString *appPath = [settings objectForKey:kHITPOpenApplicationURL];
        if (appPath) {
            _appURL = [NSURL fileURLWithPath:appPath];
            _args = [settings objectForKey:kHITPOpenApplicationArgsArray];
        }
        
    }
    return self;
}

- (void)mainAction:(id)sender {
    if (self.application) {
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "User requested to open %s with optional file %s.", [self.application cStringUsingEncoding:NSUTF8StringEncoding], [self.file cStringUsingEncoding:NSUTF8StringEncoding]);
        [[NSWorkspace sharedWorkspace] openFile:self.file withApplication:self.application andDeactivate:YES];
    } else if (self.appURL) {
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "User requested to open application at path %s with opional args %s.", [[self.appURL absoluteString] cStringUsingEncoding:NSUTF8StringEncoding], [[self.args description] cStringUsingEncoding:NSUTF8StringEncoding]);
        NSError *error = nil;
        [[NSWorkspace sharedWorkspace] launchApplicationAtURL:self.appURL options:0 configuration:@{NSWorkspaceLaunchConfigurationArguments: self.args} error:&error];
        
        if (error) {
            asl_log(NULL, NULL, ASL_LEVEL_ERR, "Error when running app:\n%s", [[error description] cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
}

@end
