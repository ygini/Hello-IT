//
//  HITPSubMenu.m
//  SubMenu
//
//  Created by Yoann Gini on 12/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPSubMenu.h"

#define kMenuItemContent @"content"
#define kMenuItemFunctionIdentifier @"functionIdentifier"
#define kMenuItemSettings @"settings"
#define kMenuItemStateSortScenario @"stateSortScenario"

#import <os/log.h>

typedef NS_ENUM(NSInteger, HITPSubMenuSortScenario) {
    HITPSubMenuSortScenarioUnavailableWin = 0,
    HITPSubMenuSortScenarioOKWin
};


@interface HITPSubMenu () <NSMenuDelegate>
@property NSArray *content;
@property NSMutableArray *subPluginInstances;
@property NSMutableArray *observedSubPluginInstances;
@property id<HITPluginsManagerProtocol> pluginsManager;
@property HITPSubMenuSortScenario stateSortScenario;
@property BOOL lastCheckWasWithOptionalDisplay;
@end

@implementation HITPSubMenu

+ (id<HITPluginProtocol>)newPlugInInstanceWithSettings:(NSDictionary*)settings {
    id instance = [[self alloc] initWithSettings:settings];
    return instance;
}

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _content = [settings objectForKey:kMenuItemContent];
        
        NSNumber *selectedScenario = [settings objectForKey:kMenuItemStateSortScenario];
        if (selectedScenario) {
            _stateSortScenario = [selectedScenario integerValue];
        } else {
            _stateSortScenario = HITPSubMenuSortScenarioUnavailableWin;
        }
        
    }
    return self;
}

-(NSMenuItem *)prepareNewMenuItem {
    NSMenuItem *menuItem = [super prepareNewMenuItem];
    
    menuItem.action = NULL;
    menuItem.target = nil;
    
    NSMenu *menu = [[NSMenu alloc] init];
    menu.delegate = self;
    self.subPluginInstances = [NSMutableArray new];
    self.observedSubPluginInstances = [NSMutableArray new];
    
    os_log_info(OS_LOG_DEFAULT, "Prepare submenu");
    
    for (NSDictionary *item in self.content) {
        os_log_info(OS_LOG_DEFAULT, "Trying to load submenu item for function %s.", [[item objectForKey:kMenuItemFunctionIdentifier] cStringUsingEncoding:NSUTF8StringEncoding]);
        Class<HITPluginProtocol> TargetPlugin = [self.pluginsManager mainClassForPluginWithFunctionIdentifier:[item objectForKey:kMenuItemFunctionIdentifier]];
        
        os_log_debug(OS_LOG_DEFAULT, "Pluing found use %s class.", [NSStringFromClass(TargetPlugin) cStringUsingEncoding:NSUTF8StringEncoding]);
        
        id<HITPluginProtocol> pluginInstance = [TargetPlugin newPlugInInstanceWithSettings:[item objectForKey:kMenuItemSettings]];
        if (pluginInstance) {
            NSObject<HITPluginProtocol> *observablePluginInstance = pluginInstance;
            
            if ([pluginInstance respondsToSelector:@selector(setPluginsManager:)]) {
                // Access to plugin manager may be needed to allow plugin to call other plugins,
                // to create a submenu for example
                [pluginInstance setPluginsManager:self.pluginsManager];
            }
            
            if ([pluginInstance respondsToSelector:@selector(testState)]) {
                BOOL skipForGlobalState = NO;
                
                if ([pluginInstance respondsToSelector:@selector(skipForGlobalState)]) {
                    skipForGlobalState = [observablePluginInstance skipForGlobalState];
                }
                
                if (!skipForGlobalState) {
                    os_log_debug(OS_LOG_DEFAULT, "Plugin instance of %s has state for global state, start observing it.", [NSStringFromClass(TargetPlugin) cStringUsingEncoding:NSUTF8StringEncoding]);
                    
                    [observablePluginInstance addObserver:self
                                               forKeyPath:@"testState"
                                                  options:0
                                                  context:nil];
                    [self.observedSubPluginInstances addObject:observablePluginInstance];
                }
            }
            
            if ([pluginInstance respondsToSelector:@selector(isNetworkRelated)]) {
                if ([pluginInstance isNetworkRelated]) {
                    os_log_debug(OS_LOG_DEFAULT, "Plugin instance of %s is network related, recording it to the plugins manager.", [NSStringFromClass(TargetPlugin) cStringUsingEncoding:NSUTF8StringEncoding]);
                    [self.pluginsManager registerPluginInstanceAsNetworkRelated:pluginInstance];
                }
            }
            
            [self.subPluginInstances addObject:pluginInstance];
            [menu addItem:[pluginInstance menuItem]];
        } else {
            os_log_error(OS_LOG_DEFAULT, "Impossible to instanciate %s (needed for %s).", [NSStringFromClass(TargetPlugin) cStringUsingEncoding:NSUTF8StringEncoding], [[item objectForKey:kMenuItemFunctionIdentifier] cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
    
    [self updateHiddenStateBasedOnRequiredKeysOnIn:menu];
    
    os_log_info(OS_LOG_DEFAULT, "Submenu ready");
    menuItem.submenu = menu;
    return menuItem;
}

- (void)updateHiddenStateBasedOnRequiredKeysOnIn:(NSMenu*)menu {
    self.lastCheckWasWithOptionalDisplay = (([NSEvent modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask) == NSEventModifierFlagOption);
    [self updateHiddenStateBasedLastCheckResult:menu];
}

- (void)updateHiddenStateBasedLastCheckResult:(NSMenu*)menu {
    for (NSMenuItem *menuItem in menu.itemArray) {
        id <HITPluginProtocol> pluginInstance = menuItem.representedObject;
        if ([pluginInstance respondsToSelector:@selector(optionalDisplay)]) {
            if (pluginInstance.optionalDisplay) {
                if (self.lastCheckWasWithOptionalDisplay) {
                    menuItem.hidden = NO;
                } else {
                    menuItem.hidden = YES;
                }
            }
        }
        
        if ([pluginInstance isKindOfClass:[HITPSubMenu class]]) {
            ((HITPSubMenu*)pluginInstance).lastCheckWasWithOptionalDisplay = self.lastCheckWasWithOptionalDisplay;
        }
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"testState"]) {
        int substate = 0;
        for (id<HITPluginProtocol> pluginInstance in self.subPluginInstances) {
            if ([pluginInstance respondsToSelector:@selector(testState)]) {
                substate |= [pluginInstance testState];
            }
        }
        
        if (self.stateSortScenario == HITPSubMenuSortScenarioOKWin) {
            if (substate&HITPluginTestStateError) self.testState = HITPluginTestStateError;
            else if (substate&HITPluginTestStateWarning) self.testState = HITPluginTestStateWarning;
            else if (substate&HITPluginTestStateOK) self.testState = HITPluginTestStateOK;
            else if (substate&HITPluginTestStateUnavailable) self.testState = HITPluginTestStateUnavailable;
        } else if (self.stateSortScenario == HITPSubMenuSortScenarioUnavailableWin) {
            if (substate&HITPluginTestStateError) self.testState = HITPluginTestStateError;
            else if (substate&HITPluginTestStateWarning) self.testState = HITPluginTestStateWarning;
            else if (substate&HITPluginTestStateUnavailable) self.testState = HITPluginTestStateUnavailable;
            else if (substate&HITPluginTestStateOK) self.testState = HITPluginTestStateOK;
        }

        os_log_info(OS_LOG_DEFAULT, "Submenu state has changed for %lu.", (unsigned long)self.testState);

    }
}

-(void)stopAndPrepareForRelease {
    for (NSObject<HITPluginProtocol> *observablePluginInstance in [self.observedSubPluginInstances reverseObjectEnumerator]) {
        [observablePluginInstance removeObserver:self forKeyPath:@"testState"];
        [self.observedSubPluginInstances removeObject:observablePluginInstance];
    }
    
    for (id<HITPluginProtocol> pluginInstance in self.subPluginInstances) {
        [pluginInstance stopAndPrepareForRelease];
    }
}

#pragma mark - NSMenuDelegate

- (void)menuWillOpen:(NSMenu *)menu {
    if (!menu.supermenu) {
        [self updateHiddenStateBasedOnRequiredKeysOnIn:menu];
    } else {
        [self updateHiddenStateBasedLastCheckResult:menu];
    }
}

- (void)menuDidClose:(NSMenu *)menu {
}

@end
