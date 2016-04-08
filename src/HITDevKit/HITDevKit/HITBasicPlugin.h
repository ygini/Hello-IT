//
//  HITBasicPlugin.h
//  HITDevKit
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import <Foundation/Foundation.h>
#import <HITDevKit/HITPluginProtocol.h>

@interface HITBasicPlugin : NSObject <HITPluginProtocol>

@property (readonly) NSMenuItem *menuItem;
@property (readonly) NSDictionary *settings;

- (instancetype)initWithSettings:(NSDictionary*)settings;

@end

@interface HITBasicPlugin (MustBeDefinedInSubclass)
- (NSMenuItem*)prepareNewMenuItem;
@end