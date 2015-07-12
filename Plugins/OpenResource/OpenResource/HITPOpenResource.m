//
//  HITPOpenResource.m
//  OpenResource
//
//  Created by Yoann Gini on 11/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPOpenResource.h"

#import <Cocoa/Cocoa.h>

#define kHITPOpenResourceTitle @"title"
#define kHITPOpenResourceURL @"URL"

@interface HITPOpenResource ()
@property NSString *title;
@property NSURL *resource;
@end

@implementation HITPOpenResource

+ (id<HITPluginProtocol>)newPlugInInstanceWithSettings:(NSDictionary*)settings {
    id instance = [[self alloc] initWithSettings:settings];
    return instance;
}

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super init];
    if (self) {
        _title = [settings objectForKey:kHITPOpenResourceTitle];
        _resource = [NSURL URLWithString:[settings objectForKey:kHITPOpenResourceURL]];
    }
    return self;
}

- (NSMenuItem*)menuItem {
    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:self.title
                                                      action:@selector(openRessource:)
                                               keyEquivalent:@""];
    
    menuItem.target = self;
    
    return menuItem;
}

- (void)openRessource:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:self.resource];
}

@end
