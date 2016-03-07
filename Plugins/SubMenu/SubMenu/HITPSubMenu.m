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

#import <asl.h>

@interface HITPSubMenu ()
@property NSArray *content;
@property NSMutableArray *subPluginInstances;
@property id<HITPluginsManagerProtocol> pluginsManager;
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
        _subPluginInstances = [NSMutableArray new];
    }
    return self;
}

-(NSMenuItem *)prepareNewMenuItem {
    NSMenuItem *menuItem = [super prepareNewMenuItem];
    
    menuItem.action = NULL;
    menuItem.target = nil;
    
    NSMenu *menu = [[NSMenu alloc] init];
    
    asl_log(NULL, NULL, ASL_LEVEL_INFO, "Prepare submenu");
    
    for (NSDictionary *item in self.content) {
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "Trying to load submenu item for function %s.", [[item objectForKey:kMenuItemFunctionIdentifier] cStringUsingEncoding:NSUTF8StringEncoding]);
        Class<HITPluginProtocol> TargetPlugin = [self.pluginsManager mainClassForPluginWithFunctionIdentifier:[item objectForKey:kMenuItemFunctionIdentifier]];
        
        asl_log(NULL, NULL, ASL_LEVEL_DEBUG, "Pluing found use %s class.", [NSStringFromClass(TargetPlugin) cStringUsingEncoding:NSUTF8StringEncoding]);
        
        id<HITPluginProtocol> pluginInstance = [TargetPlugin newPlugInInstanceWithSettings:[item objectForKey:kMenuItemSettings]];
        if (pluginInstance) {
            if ([pluginInstance respondsToSelector:@selector(setPluginsManager:)]) {
                // Access to plugin manager may be needed to allow plugin to call other plugins,
                // to create a submenu for example
                [pluginInstance setPluginsManager:self.pluginsManager];
            }
            
            if ([pluginInstance respondsToSelector:@selector(testState)]) {
                
                if ([pluginInstance respondsToSelector:@selector(skipForGlobalState)]) {
                    NSObject<HITPluginProtocol> *observablePluginInstance = pluginInstance;
                    if (![observablePluginInstance skipForGlobalState]) {
                        asl_log(NULL, NULL, ASL_LEVEL_DEBUG, "Plugin instance of %s has state for global state, start observing it.", [NSStringFromClass(TargetPlugin) cStringUsingEncoding:NSUTF8StringEncoding]);
                        
                        [observablePluginInstance addObserver:self
                                                   forKeyPath:@"testState"
                                                      options:0
                                                      context:nil];
                    }
                }
                


            }
            
            if ([pluginInstance respondsToSelector:@selector(isNetworkRelated)]) {
                if ([pluginInstance isNetworkRelated]) {
                    asl_log(NULL, NULL, ASL_LEVEL_DEBUG, "Plugin instance of %s is network related, recording it to the plugins manager.", [NSStringFromClass(TargetPlugin) cStringUsingEncoding:NSUTF8StringEncoding]);
                    [self.pluginsManager registerPluginInstanceAsNetworkRelated:pluginInstance];
                }
            }
            
            [self.subPluginInstances addObject:pluginInstance];
            [menu addItem:[pluginInstance menuItem]];
        } else {
            asl_log(NULL, NULL, ASL_LEVEL_ERR, "Impossible to instanciate %s (needed for %s).", [NSStringFromClass(TargetPlugin) cStringUsingEncoding:NSUTF8StringEncoding], [[item objectForKey:kMenuItemFunctionIdentifier] cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
    
    asl_log(NULL, NULL, ASL_LEVEL_INFO, "Submenu ready");
    menuItem.submenu = menu;
    return menuItem;
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"testState"]) {
        int substate = 0;
        for (id<HITPluginProtocol> pluginInstance in self.subPluginInstances) {
            if ([pluginInstance respondsToSelector:@selector(testState)]) {
                substate |= [pluginInstance testState];
            }
        }
        
        if (substate&HITPluginTestStateError) self.testState = HITPluginTestStateError;
        else if (substate&HITPluginTestStateWarning) self.testState = HITPluginTestStateWarning;
        else if (substate&HITPluginTestStateUnavailable) self.testState = HITPluginTestStateUnavailable;
        else if (substate&HITPluginTestStateOK) self.testState = HITPluginTestStateOK;

        asl_log(NULL, NULL, ASL_LEVEL_INFO, "Submenu state has changed for %lu.", (unsigned long)self.testState);

    }
}

@end
