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

-(NSImage *)imageForMenuItem {
    NSString *imagePath = [self.settings objectForKey:kHITSimplePluginImagePathKey];
    NSString *imageBaseName = [self.settings objectForKey:kHITSimplePluginImageBaseNameKey];
    
    if ([imagePath length] == 0 && [imageBaseName length] > 0) {
        NSString *customImageBaseFolder = [NSString stringWithFormat:@"/Library/Application Support/com.github.ygini.hello-it/CustomImageForItem"];
        
        NSString *osxMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"];
        BOOL tryDark = NO;
        NSString *imageBaseNameForDark = nil;
        if ([osxMode isEqualToString:@"Dark"]) {
            tryDark = YES;
            imageBaseNameForDark = [imageBaseName stringByAppendingString:@"-dark"];
        }

        if (tryDark) {
            imagePath = [[customImageBaseFolder stringByAppendingPathComponent:imageBaseNameForDark] stringByAppendingPathExtension:@"png"];
            
            if (![[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
                asl_log(NULL, NULL, ASL_LEVEL_INFO, "Image at path %s does not exist.", [imagePath cStringUsingEncoding:NSUTF8StringEncoding]);
                imagePath = nil;
            }
        }
        
        if ([imagePath length] == 0) {
            imagePath = [[customImageBaseFolder stringByAppendingPathComponent:imageBaseName] stringByAppendingPathExtension:@"png"];
        }

    }
    
    if (imagePath) {
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "Menu item set with image at path %s.", [imagePath cStringUsingEncoding:NSUTF8StringEncoding]);
        NSImage *accessoryImage = [[NSImage alloc] initWithContentsOfFile:imagePath];
        
        if (!accessoryImage) {
            asl_log(NULL, NULL, ASL_LEVEL_ERR, "Impossible to load image at path %s.", [imagePath cStringUsingEncoding:NSUTF8StringEncoding]);
        }
        
        return accessoryImage;
    }

    return nil;
}

-(NSMenuItem *)prepareNewMenuItem {
    NSString *title = [self localizedString:[self.settings objectForKey:kHITSimplePluginTitleKey]];
    if (!title) {
        title = @"";
    }
    
    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(mainAction:)
                                               keyEquivalent:@""];
    menuItem.target = self;
    
    menuItem.image = [self imageForMenuItem];
    
    return menuItem;
}

@end
