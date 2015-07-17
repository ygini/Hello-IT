//
//  HITSimplePlugin.h
//  HITDevKit
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import <Foundation/Foundation.h>
#import <HITDevKit/HITBasicPlugin.h>

#define kHITSimplePluginTitleKey @"title"

@interface HITSimplePlugin : HITBasicPlugin

@end

@interface HITSimplePlugin (MustBeDefinedInSubclass)
- (IBAction)mainAction:(id)sender;
@end