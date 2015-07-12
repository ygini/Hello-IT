//
//  HITPluginProtocol.h
//  Hello IT
//
//  Created by Yoann Gini on 11/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#ifndef Hello_IT_HITPluginProtocol_h
#define Hello_IT_HITPluginProtocol_h

#import <Cocoa/Cocoa.h>

@protocol HITPluginProtocol <NSObject>
@required
+ (id<HITPluginProtocol>)newPlugInInstanceWithSettings:(NSDictionary*)settings;
- (NSMenuItem*)menuItem;
@end

#endif
