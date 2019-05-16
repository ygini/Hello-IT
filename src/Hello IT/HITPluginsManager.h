//
//  HIPluginsManager.h
//  Hello IT
//
//  Created by Yoann Gini on 11/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import <Foundation/Foundation.h>
#import <HITDevKit/HITDevKit.h>

@interface HITPluginsManager : NSObject <HITPluginsManagerProtocol>

+ (instancetype)sharedInstance;
- (void)loadPluginsWithCompletionHandler:(void(^)(HITPluginsManager *pluginsManager))handler;
- (Class<HITPluginProtocol>)mainClassForPluginWithFunctionIdentifier:(NSString*)functionIdentifier;

- (void)sendNotificationWithTitle:(NSString*)title andMessage:(NSString*)message from:(id<HITPluginProtocol>)sender;
- (void)sendNotification:(NSUserNotification*)notification from:(id<HITPluginProtocol>)sender;

@end
