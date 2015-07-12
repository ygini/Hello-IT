//
//  AppDelegate.m
//  Hello IT
//
//  Created by Yoann Gini on 11/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "AppDelegate.h"

#import "HITPluginsManager.h"

#define kMenuList @"MenuList"
#define kMenuTitle @"MenuTitle"

#define kMenuItemFunctionIdentifier @"functionIdentifier"
#define kMenuItemSettings @"settings"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (strong) NSStatusItem *statusItem;
@property (strong) IBOutlet NSMenu *statusMenu;

@property NSMutableArray *pluginInstances;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    self.pluginInstances = [NSMutableArray new];
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
                                                              kMenuTitle: @"Hello IT",
                                                              kMenuList: @[
                                                                      @{kMenuItemFunctionIdentifier: @"public.title",
                                                                        kMenuItemSettings: @{
                                                                                @"title": @"Hello IT default content",
                                                                                }
                                                                        },
                                                                      @{kMenuItemFunctionIdentifier: @"public.test.http",
                                                                        kMenuItemSettings: @{
                                                                                @"title": @"Accès Internet",
                                                                                @"URL": @"http://captive.apple.com",
                                                                                @"originalString": @"73a78ff5bd7e5e88aa445826d4d6eecb",
                                                                                @"mode":@"md5",
                                                                                @"repeate": @60,
                                                                                }
                                                                        },
                                                                      @{kMenuItemFunctionIdentifier: @"public.separator"},
                                                                      @{kMenuItemFunctionIdentifier: @"public.open.resource",
                                                                        kMenuItemSettings: @{
                                                                                @"title": @"Apple",
                                                                                @"URL": @"https://www.apple.com"
                                                                                }
                                                                        },
                                                                      @{kMenuItemFunctionIdentifier: @"public.separator"},
                                                                      @{kMenuItemFunctionIdentifier: @"public.quit"}
                                                                      ]
                                                              }];
    
    [[HITPluginsManager sharedInstance] loadPluginsWithCompletionHandler:^(HITPluginsManager *pluginsManager) {
        [self loadMenu];
    }];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (void)loadMenu {
    self.statusMenu = [[NSMenu alloc] init];
    
    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    
    self.statusItem = [bar statusItemWithLength:NSVariableStatusItemLength];
    
    self.statusItem.title = [[NSUserDefaults standardUserDefaults] stringForKey:kMenuTitle];
    self.statusItem.highlightMode = YES;
    self.statusItem.menu = self.statusMenu;
    
    
    for (NSDictionary *item in [[NSUserDefaults standardUserDefaults] arrayForKey:kMenuList]) {
        Class<HITPluginProtocol> TargetPlugin = [[HITPluginsManager sharedInstance] mainClassForPluginWithFunctionIdentifier:[item objectForKeyedSubscript:kMenuItemFunctionIdentifier]];
        
        id<HITPluginProtocol> pluginInstance = [TargetPlugin newPlugInInstanceWithSettings:[item objectForKeyedSubscript:kMenuItemSettings]];
        if (pluginInstance) {
            if ([pluginInstance respondsToSelector:@selector(setPluginsManager:)]) {
                // Access to plugin manager may be needed to allow plugin to call other plugins,
                // to create a submenu for example
                [pluginInstance setPluginsManager:[HITPluginsManager sharedInstance]];
            }
            [self.pluginInstances addObject:pluginInstance];
            [self.statusMenu addItem:[pluginInstance menuItem]];
        } else {
            // TODO: log error
        }
    }
    
}

@end
