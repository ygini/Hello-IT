//
//  HITSimplePlugin.m
//  HITDevKit
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITSimplePlugin.h"

@implementation HITSimplePlugin

-(NSMenuItem *)prepareNewMenuItem {
    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:[self.settings objectForKey:kHITSimplePluginTitleKey]
                                                      action:@selector(mainAction:)
                                               keyEquivalent:@""];
    menuItem.target = self;
    
    return menuItem;
}

@end
