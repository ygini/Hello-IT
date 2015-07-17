//
//  HITPluginProtocol.h
//  Hello IT
//
//  Created by Yoann Gini on 11/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSUInteger, HITPluginTestState) {
    HITPluginTestStateNoState = 0,
    HITPluginTestStateGreen = 1 << 0,
    HITPluginTestStateOrange = 1 << 1,
    HITPluginTestStateRed = 1 << 2
};

@protocol HITPluginProtocol;

@protocol HITPluginsManagerProtocol <NSObject>
- (Class<HITPluginProtocol>)mainClassForPluginWithFunctionIdentifier:(NSString*)functionIdentifier;
@end

@protocol HITPluginProtocol <NSObject>
@required
+ (id<HITPluginProtocol>)newPlugInInstanceWithSettings:(NSDictionary*)settings;
- (NSMenuItem*)menuItem;
@optional
- (HITPluginTestState)testState;
- (void)setPluginsManager:(id<HITPluginsManagerProtocol>)manager;
@end
