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
@property (strong) id menuTrackingObserver;
@end

@implementation HITPOpenResource

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _resource = [NSURL URLWithString:[settings objectForKey:kHITPOpenResourceURL]];
        _hideIfNotAvailable = [[settings objectForKey:kHITPOpenResourceHideIfNotAvailable] boolValue];
        [self hideItemIfNeeded];

        // Recheck when any menu opens so a file:// target that appears later can unhide
        // (and one that disappears can hide). No behavior change when the flag is off.
        if (_hideIfNotAvailable) {
            __weak typeof(self) weakSelf = self;
            _menuTrackingObserver = [[NSNotificationCenter defaultCenter]
                addObserverForName:NSMenuDidBeginTrackingNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification * _Nonnull note) {
                [weakSelf hideItemIfNeeded];
            }];
        }
    }
    return self;
}

- (void)hideItemIfNeeded {
    if (!self.hideIfNotAvailable) {
        self.menuItem.hidden = NO;
        return;
    }
    // Invalid/missing URL: hide when the flag is set (nothing useful to open).
    if (!self.resource || self.resource.scheme.length == 0) {
        self.menuItem.hidden = YES;
        return;
    }
    if ([[self.resource scheme] isEqualToString:@"file"]) {
        self.menuItem.hidden = ![[NSFileManager defaultManager] fileExistsAtPath:[self.resource path]];
        if (self.menuItem.hidden) {
            os_log_info(OS_LOG_DEFAULT, "Menu item %s for resource at path %s is hidden, path does not exist.", [self.menuItem.title cStringUsingEncoding:NSUTF8StringEncoding], [[self.resource path] cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
}

- (void)stopAndPrepareForRelease {
    if (self.menuTrackingObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.menuTrackingObserver];
        self.menuTrackingObserver = nil;
    }
    [super stopAndPrepareForRelease];
}

- (void)mainAction:(id)sender {
    os_log_info(OS_LOG_DEFAULT, "User requested to open %s", [[self.resource absoluteString] cStringUsingEncoding:NSUTF8StringEncoding]);
    [[NSWorkspace sharedWorkspace] openURL:self.resource];
}

@end
