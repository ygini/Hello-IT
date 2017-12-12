//
//  HITPluginProtocol.h
//  Hello IT
//
//  Created by Yoann Gini on 11/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSUInteger, HITPluginTestState) {
    HITPluginTestStateNone = 0,
    HITPluginTestStateOK = 1 << 0,
    HITPluginTestStateWarning = 1 << 1,
    HITPluginTestStateError = 1 << 2,
    HITPluginTestStateUnavailable = 1 << 3
};

@protocol HITPluginProtocol;

@protocol HITPluginsManagerProtocol <NSObject>
- (Class<HITPluginProtocol>)mainClassForPluginWithFunctionIdentifier:(NSString*)functionIdentifier;
- (void)registerPluginInstanceAsNetworkRelated:(id<HITPluginProtocol>)plugin;
@end

@protocol HITPluginProtocol <NSObject>

@required
+ (id<HITPluginProtocol>)newPlugInInstanceWithSettings:(NSDictionary*)settings;
- (NSMenuItem*)menuItem;
@property (readonly) BOOL allowedToRun;
- (void)stopAndPrepareForRelease;

@optional
@property (readonly) BOOL optionalDisplay;
- (HITPluginTestState)testState;
- (BOOL)skipForGlobalState;

- (void)setPluginsManager:(id<HITPluginsManagerProtocol>)manager;

- (BOOL)isNetworkRelated;
- (void)generalNetworkStateUpdate:(BOOL)state;

@end
