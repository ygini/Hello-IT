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
        [[NSWorkspace sharedWorkspace] openFile:self.file withApplication:self.application andDeactivate:YES];
    } else if (self.appURL) {
        NSError *error = nil;
        [[NSWorkspace sharedWorkspace] launchApplicationAtURL:self.appURL options:0 configuration:@{NSWorkspaceLaunchConfigurationArguments: self.args} error:&error];
        
        if (error) {
            NSLog(@"Error when running %@\n%@", self.appURL, error);
        }
    }
}

@end
