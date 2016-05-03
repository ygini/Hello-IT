//
//  HITSimplePlugin.m
//  HITDevKit
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITSimplePlugin.h"

#import <asl.h>

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
    
    if (imagePath) {
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "Image set for menu item with title %s at path %s.", [title cStringUsingEncoding:NSUTF8StringEncoding], [imagePath cStringUsingEncoding:NSUTF8StringEncoding]);
        NSImage *accessoryImage = [[NSImage alloc] initWithContentsOfFile:imagePath];
        
        if (accessoryImage) {
            menuItem.image = accessoryImage;
        } else {
            asl_log(NULL, NULL, ASL_LEVEL_ERR, "Impossible to load image at path %s.", [imagePath cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
    
    
    return menuItem;
}

@end
