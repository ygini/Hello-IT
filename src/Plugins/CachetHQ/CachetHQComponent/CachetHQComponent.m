//
//  CachetHQComponent.m
//  CachetHQ
//
//  Created by Yoann Gini on 05/06/2018.
//  Copyright © 2018 Yoann Gini (Open Source Project). All rights reserved.
//

#import "CachetHQComponent.h"

#define kCachetHQBaseURL @"baseURL"
#define kCachetHQSortScenario @"stateSortScenario"

#import <asl.h>

typedef NS_ENUM(NSInteger, HITPSubMenuSortScenario) {
    HITPSubMenuSortScenarioUnavailableWin = 0,
    HITPSubMenuSortScenarioOKWin
};

@interface HITCachetHQ () <NSMenuDelegate>
@property id<HITPluginsManagerProtocol> pluginsManager;
@property HITPSubMenuSortScenario stateSortScenario;
@property NSURL *componentsAPI;
@end


@implementation HITCachetHQ

+ (id<HITPluginProtocol>)newPlugInInstanceWithSettings:(NSDictionary*)settings {
    id instance = [[self alloc] initWithSettings:settings];
    return instance;
}

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _componentsAPI = [[NSURL URLWithString:[settings objectForKey:kCachetHQBaseURL]] URLByAppendingPathComponent:@"/api/v1/components"];
        
        NSNumber *selectedScenario = [settings objectForKey:kCachetHQSortScenario];
        if (selectedScenario) {
            _stateSortScenario = [selectedScenario integerValue];
        } else {
            _stateSortScenario = HITPSubMenuSortScenarioUnavailableWin;
        }
    }
    return self;
}

- (void)periodicAction:(NSTimer *)timer {
    [[[NSURLSession sharedSession] dataTaskWithURL:self.componentsAPI
                                 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable connectionError) {
                                     if (connectionError) {
                                         self.testState = HITPluginTestStateNone;
                                         asl_log(NULL, NULL, ASL_LEVEL_INFO, "Connection error during test.");
                                         asl_log(NULL, NULL, ASL_LEVEL_DEBUG, "%s", [[connectionError description] cStringUsingEncoding:NSUTF8StringEncoding]);
                                         
                                     } else {
                                         NSError *jsonError = nil;
                                         NSDictionary * cachetInfos = [NSJSONSerialization JSONObjectWithData:data
                                                                                                      options:0
                                                                                                        error:&jsonError];
                                         
                                         if (jsonError) {
                                             self.testState = HITPluginTestStateNone;
                                             asl_log(NULL, NULL, ASL_LEVEL_INFO, "JSON decoding error.");
                                             asl_log(NULL, NULL, ASL_LEVEL_DEBUG, "%s", [[jsonError description] cStringUsingEncoding:NSUTF8StringEncoding]);
                                         } else {
                                             NSLog(@"%@", cachetInfos);
                                         }
                                     }
                                 }] resume];
}

@end
