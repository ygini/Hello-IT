//
//  AppDelegate.m
//  Hello IT
//
//  Created by Yoann Gini on 11/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "AppDelegate.h"

#import "HITPluginsManager.h"

#import "Reachability.h"

#define kMenuItemFunctionIdentifier @"functionIdentifier"
#define kMenuItemStatusBarIcon @"icon"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (strong) NSStatusItem *statusItem;
@property (strong) IBOutlet NSMenu *statusMenu;
@property id<HITPluginProtocol> statusMenuManager;
@property NSMutableArray *pluginInstances;
@property Reachability *reachability;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    self.pluginInstances = [NSMutableArray new];
    
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{
                                                              @"icon": @"default",
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
                                                                                                  @"repeat": @60,
                                                                                                  }
                                                                                          }
                                                                                        ]
                                                                                }
                                                                          },
                                                                      @{@"functionIdentifier": @"public.script.item",
                                                                        @"settings": @{
                                                                                @"path": @"~/SVN/Public/Hello-IT/Plugins/ScriptedItem/SampleScript/DisplayIP.sh",
                                                                                @"repeat": @10,
                                                                                @"network": @YES
                                                                                }
                                                                        },
                                                                      @{@"functionIdentifier": @"public.separator"},
                                                                      @{@"functionIdentifier": @"public.open.resource",
                                                                        @"settings": @{
                                                                                @"title": @"Apple",
                                                                                @"URL": @"https://www.apple.com"
                                                                                }
                                                                        },
                                                                      @{@"functionIdentifier": @"public.open.application",
                                                                        @"settings": @{
                                                                                @"title": @"Text Editor",
                                                                                @"app": @"TextEdit"
                                                                                }
                                                                        },
                                                                      @{@"functionIdentifier": @"public.open.application",
                                                                        @"settings": @{
                                                                                @"title": @"TextEdit Info.plist",
                                                                                @"appURL": @"/Applications/TextEdit.app",
                                                                                @"args": @[@"/Applications/TextEdit.app/Contents/Info.plist"]
                                                                                }
                                                                        },
                                                                      @{@"functionIdentifier": @"public.separator"},
                                                                      @{@"functionIdentifier": @"public.quit"}
                                                                      ]
                                                              }];
        
    [[HITPluginsManager sharedInstance] loadPluginsWithCompletionHandler:^(HITPluginsManager *pluginsManager) {
        [self loadMenu];
        
        self.reachability = [Reachability reachabilityForLocalNetwork];
        [self.reachability startNotifier];
    }];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
    
    [self.reachability stopNotifier];
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
    
    NSString *iconString = [[NSUserDefaults standardUserDefaults] stringForKey:kMenuItemStatusBarIcon];
    NSImage *icon = nil;
    
    if (iconString) {
        if ([iconString isEqualToString:@"default"]) {
            icon = [NSImage imageNamed:@"statusbar"];
        } else if ([[NSFileManager defaultManager] fileExistsAtPath:iconString]) {
            icon = [[NSImage alloc] initWithContentsOfFile:iconString];
        }
    }
    
    if (icon) {
        self.statusItem.image = icon;
    } else {
        self.statusItem.title = [self.statusMenuManager menuItem].title;
    }
    
    self.statusItem.highlightMode = YES;
    self.statusItem.menu = [self.statusMenuManager menuItem].submenu;
}

@end
