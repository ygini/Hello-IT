//
//  AppDelegate.m
//  Hello IT
//
//  Created by Yoann Gini on 11/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "AppDelegate.h"

#import "HITPluginsManager.h"

#define kMenuItemFunctionIdentifier @"functionIdentifier"

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
                                                              @"title": @"Hello IT",
                                                              @"content": @[
                                                                      @{@"functionIdentifier": @"public.title",
                                                                        @"settings": @{
                                                                                @"title": @"Hello IT default content",
                                                                                }
                                                                        },
                                                                      @{@"functionIdentifier": @"public.submenu",
                                                                        @"settings": @{
                                                                                @"title": @"Services state",
                                                                                @"content": @[
                                                                                        @{@"functionIdentifier": @"public.test.http",
                                                                                          @"settings": @{
                                                                                                  @"title": @"Internet",
                                                                                                  @"URL": @"http://captive.apple.com",
                                                                                                  @"originalString": @"73a78ff5bd7e5e88aa445826d4d6eecb",
                                                                                                  @"mode":@"md5",
                                                                                                  @"repeate": @60,
                                                                                                  }
                                                                                          }
                                                                                        ]
                                                                                }
                                                                          },
                                                                      @{@"functionIdentifier": @"public.separator"},
                                                                      @{@"functionIdentifier": @"public.open.resource",
                                                                        @"settings": @{
                                                                                @"title": @"Apple",
                                                                                @"URL": @"https://www.apple.com"
                                                                                }
                                                                        },
                                                                      @{@"functionIdentifier": @"public.separator"},
                                                                      @{@"functionIdentifier": @"public.quit"}
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
    NSString *menuBuilder = [[NSUserDefaults standardUserDefaults] stringForKey:kMenuItemFunctionIdentifier];
    
    if ([menuBuilder length] == 0) {
        menuBuilder = @"public.submenu";
    }
    
    Class<HITPluginProtocol> SubMenuPlugin = [[HITPluginsManager sharedInstance] mainClassForPluginWithFunctionIdentifier:menuBuilder];
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
