//
//  HITBasicPlugin.m
//  HITDevKit
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITBasicPlugin.h"

#define kHITPPptionalDisplay @"optionalDisplay"

@interface HITBasicPlugin () {
    NSMenuItem *_menuItem;
}

@property BOOL allowedToRun;
@property BOOL optionalDisplay;

@end

@implementation HITBasicPlugin

+ (id<HITPluginProtocol>)newPlugInInstanceWithSettings:(NSDictionary*)settings {
    id instance = [[self alloc] initWithSettings:settings];
    return instance;
}

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super init];
    if (self) {
        _allowedToRun = YES;
        _settings = settings;
        
        _optionalDisplay = [[settings objectForKey:kHITPPptionalDisplay] boolValue];
    }
    return self;
}

-(NSMenuItem *)menuItem {
    if (!_menuItem) {
         _menuItem = [self prepareNewMenuItem];
        _menuItem.representedObject = self;
    }
    
    return _menuItem;
}

- (void)stopAndPrepareForRelease {
    self.allowedToRun = NO;
}

- (NSString*)localizedString:(id)dictionaryOrArray {
    if ([dictionaryOrArray isKindOfClass:[NSDictionary class]]) {
        NSString *selectedValue = nil;
        
        for (NSString *localIdentifier in @[
                                            [[NSLocale currentLocale] localeIdentifier],
                                            [[NSLocale currentLocale] languageCode],
                                            @"en"]) {
            selectedValue = [dictionaryOrArray objectForKey:localIdentifier];
            if (selectedValue) {
                break;
            }
        }
        
        return selectedValue;
    } else {
        return dictionaryOrArray;
    }
}
@end
