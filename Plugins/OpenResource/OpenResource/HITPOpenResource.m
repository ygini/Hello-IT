//
//  HITPOpenResource.m
//  OpenResource
//
//  Created by Yoann Gini on 11/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPOpenResource.h"

#import <Cocoa/Cocoa.h>

#define kHITPOpenResourceURL @"URL"

@interface HITPOpenResource ()
@property NSURL *resource;
@end

@implementation HITPOpenResource

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _resource = [NSURL URLWithString:[settings objectForKey:kHITPOpenResourceURL]];
    }
    return self;
}

- (void)mainAction:(id)sender {
    [[NSWorkspace sharedWorkspace] openURL:self.resource];
}

@end
