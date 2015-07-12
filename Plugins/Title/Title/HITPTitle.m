//
//  HITPTitle.m
//  Title
//
//  Created by Yoann Gini on 11/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPTitle.h"

#define kHITPTitle @"title"

@interface HITPTitle ()
@property NSString *title;
@end
@implementation HITPTitle

+ (id<HITPluginProtocol>)newPlugInInstanceWithSettings:(NSDictionary*)settings {
    id instance = [[self alloc] initWithSettings:settings];
    return instance;
}

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super init];
    if (self) {
        _title = [settings objectForKey:kHITPTitle];
    }
    return self;
}

- (NSMenuItem*)menuItem {
    NSMenuItem *menuItem = [[NSMenuItem alloc] init];
    menuItem.title = self.title;
    
    menuItem.target = self;
    
    return menuItem;
}

@end
