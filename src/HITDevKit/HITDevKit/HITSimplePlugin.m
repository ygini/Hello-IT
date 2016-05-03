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
    NSString *title = [self.settings objectForKey:kHITSimplePluginTitleKey];
    if (!title) {
        title = @"";
    }
    
    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(mainAction:)
                                               keyEquivalent:@""];
    menuItem.target = self;
    
    NSString *imagePath = [self.settings objectForKey:kHITSimplePluginImagePathKey];
    
    NSImage *accessoryImage = [[NSImage alloc] initWithContentsOfFile:imagePath];
    menuItem.image = accessoryImage;
    
    return menuItem;
}

@end
