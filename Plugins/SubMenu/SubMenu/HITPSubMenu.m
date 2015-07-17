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
    
    for (NSDictionary *item in self.content) {
        Class<HITPluginProtocol> TargetPlugin = [self.pluginsManager mainClassForPluginWithFunctionIdentifier:[item objectForKey:kMenuItemFunctionIdentifier]];
        
        id<HITPluginProtocol> pluginInstance = [TargetPlugin newPlugInInstanceWithSettings:[item objectForKey:kMenuItemSettings]];
        if (pluginInstance) {
            if ([pluginInstance respondsToSelector:@selector(setPluginsManager:)]) {
                // Access to plugin manager may be needed to allow plugin to call other plugins,
                // to create a submenu for example
                [pluginInstance setPluginsManager:self.pluginsManager];
            }
            
            if ([pluginInstance respondsToSelector:@selector(testState)]) {
                NSObject<HITPluginProtocol> *observablePluginInstance = pluginInstance;
                [observablePluginInstance addObserver:self
                                           forKeyPath:@"testState"
                                              options:0
                                              context:nil];
            }
            
            [self.subPluginInstances addObject:pluginInstance];
            [menu addItem:[pluginInstance menuItem]];
        } else {
            NSLog(@"Target plugin class %@ for function identifier %@ is unable to create any instance with +newPlugInInstanceWithSettings: method.", TargetPlugin, [item objectForKey:kMenuItemFunctionIdentifier]);
        }
    }
    
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
        
        if (substate&HITPluginTestStateRed) self.testState = HITPluginTestStateRed;
        else if (substate&HITPluginTestStateOrange) self.testState = HITPluginTestStateOrange;
        else if (substate&HITPluginTestStateGreen) self.testState = HITPluginTestStateGreen;
        
    }
}

@end
