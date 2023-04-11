//
//  HITPOpenResource.m
//  OpenResource
//
//  Created by Yoann Gini on 11/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPOpenResource.h"

#import <Cocoa/Cocoa.h>
#import <os/log.h>
#define kHITPOpenResourceURL @"URL"
#define kHITPOpenResourceHideIfNotAvailable @"hideIfNotAvailable"

@interface HITPOpenResource ()
@property NSURL *resource;
@property BOOL hideIfNotAvailable;
@end

@implementation HITPOpenResource

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _resource = [NSURL URLWithString:[settings objectForKey:kHITPOpenResourceURL]];
        _hideIfNotAvailable = [[settings objectForKey:kHITPOpenResourceHideIfNotAvailable] boolValue];
        
        [self hideItemIfNeeded];
    }
    return self;
}

- (void)hideItemIfNeeded {
    if (self.hideIfNotAvailable) {
        if ([[self.resource scheme] isEqualToString:@"file"]) {
            self.menuItem.hidden = ![[NSFileManager defaultManager] fileExistsAtPath:[self.resource path]];
            if (self.menuItem.hidden) {
                os_log_info(OS_LOG_DEFAULT, "Menu item %s for resource at path %s is hidden, path does not exist.", [self.menuItem.title cStringUsingEncoding:NSUTF8StringEncoding], [[self.resource path] cStringUsingEncoding:NSUTF8StringEncoding]);
            }
        }
    } else {
        self.menuItem.hidden = NO;
    }
}


- (void)mainAction:(id)sender {
    os_log_info(OS_LOG_DEFAULT, "User requested to open %s", [[self.resource absoluteString] cStringUsingEncoding:NSUTF8StringEncoding]);
    [[NSWorkspace sharedWorkspace] openURL:self.resource];
}

@end
