//
//  HITAdvancedPlugin.m
//  HITDevKit
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITAdvancedPlugin.h"
#import <os/log.h>

@interface HITAdvancedPlugin () {
    HITPluginTestState _testState;
}
@property id<HITPluginsManagerProtocol> pluginsManager;

@end

@implementation HITAdvancedPlugin

@dynamic testState;

- (void)updateMenuItemState {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSString *notificationMessage = nil;
        switch (self.testState) {
            case HITPluginTestStateError:
                self.menuItem.image = [[NSImage alloc] initWithContentsOfFile:[[NSBundle bundleWithIdentifier:@"com.github.ygini.HITDevKit"] pathForResource:@"Error"
                                                                                                                                                      ofType:@"tiff"]];
                notificationMessage = [self localizedString:[self.settings objectForKey:kHITNotificationMessageForErrorKey]];
                break;
            case HITPluginTestStateOK:
                self.menuItem.image = [[NSImage alloc] initWithContentsOfFile:[[NSBundle bundleWithIdentifier:@"com.github.ygini.HITDevKit"] pathForResource:@"OK"
                                                                                                                                                      ofType:@"tiff"]];
                notificationMessage = [self localizedString:[self.settings objectForKey:kHITNotificationMessageForOKKey]];
                break;
            case HITPluginTestStateWarning:
                self.menuItem.image = [[NSImage alloc] initWithContentsOfFile:[[NSBundle bundleWithIdentifier:@"com.github.ygini.HITDevKit"] pathForResource:@"Warning"
                                                                                                                                                      ofType:@"tiff"]];
                notificationMessage = [self localizedString:[self.settings objectForKey:kHITNotificationMessageForWarningKey]];
                break;
            case HITPluginTestStateUnavailable:
                self.menuItem.image = [[NSImage alloc] initWithContentsOfFile:[[NSBundle bundleWithIdentifier:@"com.github.ygini.HITDevKit"] pathForResource:@"Unavailable"
                                                                                                                                                      ofType:@"tiff"]];
                notificationMessage = [self localizedString:[self.settings objectForKey:kHITNotificationMessageForUnavailableKey]];
                break;
            case HITPluginTestStateNone:
            default:
                self.menuItem.image = [self imageForMenuItem];
                notificationMessage = [self localizedString:[self.settings objectForKey:kHITNotificationMessageForNoneKey]];
                break;
        }
        if (notificationMessage) {
            [self sendNotificationWithMessage:notificationMessage];
        }
    });
}

-(void)sendNotificationWithMessage:(NSString*)message {
    [self.pluginsManager sendNotificationWithTitle:self.menuItem.title andMessage:message from:self];
}

-(HITPluginTestState)testState {
    return _testState;
}

-(void)setTestState:(HITPluginTestState)testState {
    if (_testState != testState) {
        _testState = testState;
        [self updateMenuItemState];
    }
}

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _skipForGlobalState = [[settings objectForKey:kHITAdvancedPluginSkipForGlobalStateKey] boolValue];
    }
    return self;
}

@end
