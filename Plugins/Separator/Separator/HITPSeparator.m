//
//  HITPSeparator.m
//  Separator
//
//  Created by Yoann Gini on 11/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPSeparator.h"

@implementation HITPSeparator

+ (id<HITPluginProtocol>)newPlugInInstanceWithSettings:(NSDictionary*)settings {
    id instance = [self new];
    return instance;
}

- (NSMenuItem*)menuItem {    
    return [NSMenuItem separatorItem];
}


@end
