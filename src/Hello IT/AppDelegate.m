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
#import <QuartzCore/QuartzCore.h>

#import <asl.h>

#define kMenuItemFunctionIdentifier @"functionIdentifier"
#define kMenuItemStatusBarTitle @"title"
#define kMenuItemContent @"content"
#define kMenuItemSettings @"settings"
#define kMenuItemAllowSubdomains @"allowSubdomains"

@interface AppDelegate () 

@property (weak) IBOutlet NSWindow *window;
@property (strong) NSStatusItem *statusItem;
@property id<HITPluginProtocol> statusMenuManager;
@property Reachability *reachability;

@property id notificationObjectForInterfaceTheme;
@property id notificationObjectForMDMUpdate;

@property BOOL menuOK;


@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.menuOK = NO;
    
    asl_add_log_file(NULL, STDERR_FILENO);
    
    // This is a sample configuration to allow Hello IT to run without any custom settings.
    // You don't have to edit this code and rebuild the apps to use it, you just have to
    // customize com.github.ygini.Hello-IT like indicated here on the documentation
    // https://github.com/ygini/Hello-IT/wiki/Preferences
    
    
    if ([[[NSUserDefaults standardUserDefaults] arrayForKey:@"content"] count] == 0) {
        asl_log(NULL, NULL, ASL_LEVEL_WARNING, "No settings found in com.github.ygini.Hello-IT domain. Loading sample one.");
        
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{
                                                                  @"functionIdentifier": @"public.submenu",
                                                                  @"settings": @{
                                                                          @"content": @[
                                                                                  @{@"functionIdentifier": @"public.title",
                                                                                    @"settings": @{
                                                                                            @"title": @"You Mac isn't managed, please call your IT support",
                                                                                            }
                                                                                    },
                                                                                  @{@"functionIdentifier": @"public.script.item",
                                                                                    @"settings": @{
                                                                                            @"script": @"com.github.ygini.hello-it.ip.sh",
                                                                                            @"skipForGlobalState": @YES,
                                                                                            @"options": @[@"-m", @"2" ]
                                                                                            
                                                                                            }
                                                                                    },
                                                                                  @{@"functionIdentifier": @"public.script.item",
                                                                                    @"settings": @{
                                                                                            @"script": @"com.github.ygini.hello-it.hostname.sh",
                                                                                            @"skipForGlobalState": @YES,
                                                                                            @"args": @{
                                                                                                    @"format": @"%C (%H)"
                                                                                                    }
                                                                                            }
                                                                                    },
                                                                                  @{@"functionIdentifier": @"public.separator"},
                                                                                  @{@"functionIdentifier": @"public.quit"}
                                                                                  ]
                                                                          }
                                                                  }];

    }
    
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"loglevel"]) {
        asl_set_filter(NULL, ASL_FILTER_MASK_UPTO([[NSUserDefaults standardUserDefaults] integerForKey:@"loglevel"]));
    }
    
    self.notificationObjectForMDMUpdate = [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"com.apple.MCX._managementStatusChangedForDomains"
                                                                                                      object:nil
                                                                                                       queue:nil
                                                                                                  usingBlock:^(NSNotification * _Nonnull note) {
                                                                                                      NSArray *domains = [note.userInfo objectForKey:@"com.apple.MCX.changedDomains"];
                                                                                                      
                                                                                                      for (NSString *domain in domains) {
                                                                                                          if ([[domain lowercaseString] rangeOfString:[[[NSBundle mainBundle] bundleIdentifier] lowercaseString]].location == 0) {
                                                                                                              [self reloadHelloIT];
                                                                                                          }
                                                                                                      }
                                                                                                      
                                                             }];
    
    
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    
    [self reloadHelloIT];
    
    self.reachability = [Reachability reachabilityWithHostname:@"captive.apple.com"];
    [self.reachability startNotifier];
    
    self.notificationObjectForInterfaceTheme = [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"AppleInterfaceThemeChangedNotification"
                                                                                                           object:nil
                                                                                                            queue:nil
                                                                                                       usingBlock:^(NSNotification * _Nonnull note) {
                                                                                                           [self updateStatusItem];
                                                                                            }];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
    
    [self.reachability stopNotifier];
    [[NSNotificationCenter defaultCenter] removeObserver:self.notificationObjectForMDMUpdate];
    [[NSNotificationCenter defaultCenter] removeObserver:self.notificationObjectForInterfaceTheme];
}

- (void)reloadHelloIT {
    self.menuOK = NO;
    
    if (self.statusMenuManager) {
        NSObject<HITPluginProtocol> *menuManagerPlugin = self.statusMenuManager;
        [menuManagerPlugin stopAndPrepareForRelease];
    }
    
    
    [[HITPluginsManager sharedInstance] loadPluginsWithCompletionHandler:^(HITPluginsManager *pluginsManager) {
        [self loadMenu];
    }];
}

- (void)updateStatusItem {
    if (!self.menuOK) {
        return;
    }
    
    HITPluginTestState statusMenuState = HITPluginTestStateNone;
    
    if ([self.statusMenuManager respondsToSelector:@selector(testState)]) {
        statusMenuState |= [self.statusMenuManager testState];
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "General state has changed for %lu.", (unsigned long)statusMenuState);
    }
    
    if ([[self.statusMenuManager menuItem].title length] == 0) {
        NSString *imageName = nil;
        NSString *imageNameForDark = nil;
        BOOL tryDark = NO;
        NSImage *icon;
        
        switch (statusMenuState) {
            case HITPluginTestStateError:
                imageName = @"statusbar-error";
                break;
            case HITPluginTestStateUnavailable:
                imageName = @"statusbar-unavailable";
                break;
            case HITPluginTestStateWarning:
                imageName = @"statusbar-warning";
                break;
            case HITPluginTestStateOK:
                imageName = @"statusbar-ok";
                break;
            default:
                imageName = @"statusbar";
                break;
        }
        
        NSString *osxMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"];
        
        if ([osxMode isEqualToString:@"Dark"]) {
            tryDark = YES;
            imageNameForDark = [imageName stringByAppendingString:@"-dark"];
        }
        
        NSString *customStatusBarIconBaseFolder = [NSString stringWithFormat:@"/Library/Application Support/com.github.ygini.hello-it/CustomStatusBarIcon"];

        NSString *finalPath = [[customStatusBarIconBaseFolder stringByAppendingPathComponent:imageName] stringByAppendingPathExtension:@"tiff"];
        
        NSString *finalPathForDark = nil;
        if (tryDark) {
            finalPathForDark = [[customStatusBarIconBaseFolder stringByAppendingPathComponent:imageNameForDark] stringByAppendingPathExtension:@"tiff"];
            asl_log(NULL, NULL, ASL_LEVEL_INFO, "We will look for menu item icon at path %s.", [finalPathForDark cStringUsingEncoding:NSUTF8StringEncoding]);
        }
        
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "We will look for menu item icon at path %s.", [finalPath cStringUsingEncoding:NSUTF8StringEncoding]);
        
        if ([[NSFileManager defaultManager] fileExistsAtPath:finalPathForDark]) {
            icon = [[NSImage alloc] initWithContentsOfFile:finalPathForDark];
            
        } else if ([[NSFileManager defaultManager] fileExistsAtPath:finalPath]) {
            icon = [[NSImage alloc] initWithContentsOfFile:finalPath];
            
        } else {
            if (tryDark) {
                asl_log(NULL, NULL, ASL_LEVEL_INFO, "Default dark icon will be used.");
                icon = [NSImage imageNamed:imageNameForDark];
            } else {
                asl_log(NULL, NULL, ASL_LEVEL_INFO, "Default icon will be used.");
                icon = [NSImage imageNamed:imageName];
            }
        }
        
        self.statusItem.image = icon;
    } else {
        NSColor *textColor = nil;
        NSString *osxMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"];

        switch (statusMenuState) {
            case HITPluginTestStateError:
                textColor = [NSColor redColor];
                break;
            case HITPluginTestStateUnavailable:
                textColor = [NSColor grayColor];
                break;
            case HITPluginTestStateWarning:
                textColor = [NSColor orangeColor];
                break;
            default:
                if ([osxMode isEqualToString:@"Dark"]) {
                    textColor = [NSColor whiteColor];
                } else {
                    textColor = [NSColor blackColor];
                }
                break;
        }
        
        NSAttributedString *title = [[NSAttributedString alloc] initWithString:[self.statusMenuManager menuItem].title
                                                                    attributes:@{NSForegroundColorAttributeName: textColor}];
        
        self.statusItem.attributedTitle = title;
    }
}

- (void)loadMenu {
    NSMutableDictionary *compositeSettings = [NSMutableDictionary dictionaryWithCapacity:2];

    NSArray *oldStyleRootContent = [[NSUserDefaults standardUserDefaults] arrayForKey:kMenuItemContent];
    
    if (oldStyleRootContent) {
        // We have pre 1.3 preferences, were root item is the settings for public.submenu instead of regular item settings
        // We need to rebuild the settings to fill 1.3+ needs, with root item being exactly like another item
        NSString *statusBarTitle = [[NSUserDefaults standardUserDefaults] stringForKey:kMenuItemStatusBarTitle];
        [compositeSettings setObject:@"public.submenu" forKey:kMenuItemFunctionIdentifier];
        
        if (statusBarTitle) {
            [compositeSettings setObject:@{kMenuItemContent: oldStyleRootContent, kMenuItemStatusBarTitle:statusBarTitle} forKey:kMenuItemSettings];
        } else {
            [compositeSettings setObject:@{kMenuItemContent: oldStyleRootContent} forKey:kMenuItemSettings];
        }
        
    } else {
        // 1.3+ version support standard function and settings keys at root, allowing end IT to use custom functions more easily
        
        [compositeSettings setObject:[[NSUserDefaults standardUserDefaults] stringForKey:kMenuItemFunctionIdentifier] forKey:kMenuItemFunctionIdentifier];
        [compositeSettings setObject:[[NSUserDefaults standardUserDefaults] dictionaryForKey:kMenuItemSettings] forKey:kMenuItemSettings];
        
    }
    
    BOOL allowSubdomains = [[NSUserDefaults standardUserDefaults] boolForKey:kMenuItemAllowSubdomains];
    
    if (allowSubdomains) {
        // HIT support composed menu item, all user's preferences starting with "bundleID." will be loaded as first item
        NSArray *relatedDomainNames = [[[[NSUserDefaults standardUserDefaults] persistentDomainNames] filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"SELF BEGINSWITH[c] %@", [[[NSBundle mainBundle] bundleIdentifier] stringByAppendingString:@"."]]] sortedArrayUsingComparator:^NSComparisonResult(NSString *obj1, NSString *obj2) {
            return [obj2 compare:obj1];
        }];
        
        NSMutableArray *updatedContent = [[[compositeSettings objectForKey:kMenuItemSettings] objectForKey:kMenuItemContent] mutableCopy];
        
        for (NSString *domainName in relatedDomainNames) {
            asl_log(NULL, NULL, ASL_LEVEL_INFO, "Adding nested preference domain %s as first item.", [domainName UTF8String]);
            NSMutableDictionary *subDomain = [[[NSUserDefaults standardUserDefaults] persistentDomainForName:domainName] mutableCopy];
            
            [updatedContent insertObject:subDomain
                                 atIndex:0];
        }
        
        NSMutableDictionary *rootItemSettings = [[compositeSettings objectForKey:kMenuItemSettings] mutableCopy];
        [rootItemSettings setObject:updatedContent forKey:kMenuItemContent];
        [compositeSettings setObject:rootItemSettings forKey:kMenuItemSettings];
    }
    
    if ([self.statusMenuManager respondsToSelector:@selector(testState)]) {
        NSObject<HITPluginProtocol> *observablePluginInstance = self.statusMenuManager;
        [observablePluginInstance removeObserver:self forKeyPath:@"testState" context:nil];
    }
    
    Class<HITPluginProtocol> SubMenuPlugin = [[HITPluginsManager sharedInstance] mainClassForPluginWithFunctionIdentifier:[compositeSettings objectForKey:kMenuItemFunctionIdentifier]];
    self.statusMenuManager = [SubMenuPlugin newPlugInInstanceWithSettings:[compositeSettings objectForKey:kMenuItemSettings]];
    if (self.statusMenuManager) {
        if ([self.statusMenuManager respondsToSelector:@selector(setPluginsManager:)]) {
            [self.statusMenuManager setPluginsManager:[HITPluginsManager sharedInstance]];
        }
    }
    
    if ([self.statusMenuManager respondsToSelector:@selector(testState)]) {
        NSObject<HITPluginProtocol> *observablePluginInstance = self.statusMenuManager;
        [observablePluginInstance addObserver:self
                                   forKeyPath:@"testState"
                                      options:0
                                      context:nil];
    }
    
    self.statusItem.highlightMode = YES;
    self.statusItem.menu = [self.statusMenuManager menuItem].submenu;
    
    self.menuOK = YES;
    [self updateStatusItem];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"testState"]) {
        [self updateStatusItem];
    }
}



@end
