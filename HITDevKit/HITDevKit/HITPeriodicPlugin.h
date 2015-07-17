//
//  HITPeriodicPlugin.h
//  HITDevKit
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import <HITDevKit/HITDevKit.h>

#define kHITPeriodicPluginRepeatKey @"repeat"

@interface HITPeriodicPlugin : HITAdvancedPlugin

@end

@interface HITPeriodicPlugin (MustBeDefinedInSubclass)
- (void)periodicAction:(NSTimer *)timer;
@end