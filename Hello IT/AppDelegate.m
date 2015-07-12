//
//  AppDelegate.m
//  Hello IT
//
//  Created by Yoann Gini on 11/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "AppDelegate.h"

#import "HITPluginsManager.h"

#define kMenuList @"content"
#define kMenuTitle @"title"

#define kMenuItemFunctionIdentifier @"functionIdentifier"
#define kMenuItemSettings @"settings"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (strong) NSStatusItem *statusItem;
@property (strong) IBOutlet NSMenu *statusMenu;
@property id<HITPluginProtocol> statusMenuManager;
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
    
    [[[NSUserDefaults standardUserDefaults] dictionaryRepresentation] writeToFile:[@"~/Desktop/pref.plist" stringByExpandingTildeInPath] atomically:YES];
    
    [[HITPluginsManager sharedInstance] loadPluginsWithCompletionHandler:^(HITPluginsManager *pluginsManager) {
        [self loadMenu];
    }];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
}

- (void)loadMenu {
    
    Class<HITPluginProtocol> SubMenuPlugin = [[HITPluginsManager sharedInstance] mainClassForPluginWithFunctionIdentifier:@"public.submenu"];
    self.statusMenuManager = [SubMenuPlugin newPlugInInstanceWithSettings:[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]];
    if (self.statusMenuManager) {
        if ([self.statusMenuManager respondsToSelector:@selector(setPluginsManager:)]) {
            [self.statusMenuManager setPluginsManager:[HITPluginsManager sharedInstance]];
        }
    }
    
    self.statusMenu = [[NSMenu alloc] init];
    
    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    
    self.statusItem = [bar statusItemWithLength:NSVariableStatusItemLength];
    
    self.statusItem.title = [self.statusMenuManager menuItem].title;
    self.statusItem.highlightMode = YES;
    self.statusItem.menu = [self.statusMenuManager menuItem].submenu;
}

@end
