//
//  HITBasicPlugin.m
//  HITDevKit
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITBasicPlugin.h"

@interface HITBasicPlugin () {
    NSMenuItem *_menuItem;
}

@end

@implementation HITBasicPlugin

+ (id<HITPluginProtocol>)newPlugInInstanceWithSettings:(NSDictionary*)settings {
    id instance = [[self alloc] initWithSettings:settings];
    return instance;
}

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super init];
    if (self) {
        _settings = settings;
    }
    return self;
}

-(NSMenuItem *)menuItem {
    if (!_menuItem) {
         _menuItem = [self prepareNewMenuItem];
    }
    
    return _menuItem;
}


@end
