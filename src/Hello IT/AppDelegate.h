//
//  AppDelegate.h
//  Hello IT
//
//  Created by Yoann Gini on 11/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class Reachability;

@interface AppDelegate : NSObject <NSApplicationDelegate>
@property (readonly) Reachability *reachability;
@end

