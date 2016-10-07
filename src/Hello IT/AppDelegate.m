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

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (strong) NSStatusItem *statusItem;
@property (strong) IBOutlet NSMenu *statusMenu;
@property id<HITPluginProtocol> statusMenuManager;
@property NSMutableArray *pluginInstances;
@property Reachability *reachability;

@property (nonatomic) HITPluginTestState testState;

@property id notificationOjectForInterfaceTheme;
@property id notificationOjectForMDMUpdate;

@property BOOL menuOK;


@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.menuOK = NO;
    self.pluginInstances = [NSMutableArray new];
    
    asl_add_log_file(NULL, STDERR_FILENO);
    
    // This is a sample configuration to allow Hello IT to run without any custom settings.
    // You don't have to edit this code and rebuild the apps to use it, you just have to
    // customize com.github.ygini.Hello-IT like indicated here on the documentation
    // https://github.com/ygini/Hello-IT/wiki/Preferences
    
    
    if ([[[NSUserDefaults standardUserDefaults] arrayForKey:@"content"] count] == 0) {
        asl_log(NULL, NULL, ASL_LEVEL_WARNING, "No settings found in com.github.ygini.Hello-IT domain. Loading sample one.");
        
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{
                                                                  @"content": @[
                                                                          @{@"functionIdentifier": @"public.title",
                                                                            @"settings": @{
                                                                                    @"title": @"Hello IT default content",
                                                                                    }
                                                                            },
                                                                          @{@"functionIdentifier": @"public.open.resource",
                                                                            @"settings": @{
                                                                                    @"title": @"Hello IT Documentation",
                                                                                    @"URL": @"https://github.com/ygini/Hello-IT/wiki",
                                                                                    @"imagePath": @"/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/HelpIcon.icns"

                                                                                    }
                                                                            },
                                                                          @{@"functionIdentifier": @"public.open.resource",
                                                                            @"settings": @{
                                                                                    @"title": @"The page needed to deploy your custom content",
                                                                                    @"URL": @"https://github.com/ygini/Hello-IT/wiki/Preferences"
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
                                                                  }];

    }
    
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"loglevel"]) {
        asl_set_filter(NULL, ASL_FILTER_MASK_UPTO([[NSUserDefaults standardUserDefaults] integerForKey:@"loglevel"]));
    }
    
    self.notificationOjectForMDMUpdate = [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"com.apple.MCX._managementStatusChangedForDomains"
                                                                                                      object:nil
                                                                                                       queue:nil
                                                                                                  usingBlock:^(NSNotification * _Nonnull note) {
                                                                                                      NSArray *domains = [note.userInfo objectForKey:@"com.apple.MCX.changedDomains"];
                                                                                                      if ([domains containsObject:[[NSBundle mainBundle] bundleIdentifier]]) {
                                                                                                          [self reloadHelloIT];
                                                                                                      }
                                                                                                      
                                                             }];
    
    [self reloadHelloIT];
    
    self.reachability = [Reachability reachabilityWithHostname:@"captive.apple.com"];
    [self.reachability startNotifier];
    
    self.notificationOjectForInterfaceTheme = [[NSDistributedNotificationCenter defaultCenter] addObserverForName:@"AppleInterfaceThemeChangedNotification"
                                                                                                           object:nil
                                                                                                            queue:nil
                                                                                                       usingBlock:^(NSNotification * _Nonnull note) {
                                                                                                           [self updateStatusItem];
                                                                                            }];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
    // Insert code here to tear down your application
    
    [self.reachability stopNotifier];
    [[NSNotificationCenter defaultCenter] removeObserver:self.notificationOjectForMDMUpdate];
    [[NSNotificationCenter defaultCenter] removeObserver:self.notificationOjectForInterfaceTheme];
}

- (void)reloadHelloIT {
    self.menuOK = NO;
    
    if (self.statusMenuManager) {
        NSObject<HITPluginProtocol> *menuManagerPlugin = self.statusMenuManager;
        [menuManagerPlugin stopAndPrepareForRelease];
    }
    
    
    self.statusMenu = [[NSMenu alloc] init];
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    
    [[HITPluginsManager sharedInstance] loadPluginsWithCompletionHandler:^(HITPluginsManager *pluginsManager) {
        [self loadMenu];
    }];
}

- (void)updateStatusItem {
    
    if (!self.menuOK) {
        return;
    }
    
    NSString *iconTitle = [[NSUserDefaults standardUserDefaults] stringForKey:kMenuItemStatusBarTitle];
    
    if ([iconTitle length] == 0) {
        NSString *imageName = nil;
        NSString *imageNameForDark = nil;
        BOOL tryDark = NO;
        NSImage *icon;
        
        switch (self.testState) {
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

        
        NSString *finalPath = [[customStatusBarIconBaseFolder stringByAppendingPathComponent:imageName] stringByAppendingPathExtension:@"png"];
        
        NSString *finalPathForDark = nil;
        if (tryDark) {
            finalPathForDark = [[customStatusBarIconBaseFolder stringByAppendingPathComponent:imageNameForDark] stringByAppendingPathExtension:@"png"];
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
        
        switch (self.testState) {
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
                textColor = [NSColor blackColor];
                break;
        }
        
        NSAttributedString *title = [[NSAttributedString alloc] initWithString:[self.statusMenuManager menuItem].title
                                                                    attributes:@{NSForegroundColorAttributeName: textColor}];
        
        self.statusItem.attributedTitle = title;
    }
}

- (void)loadMenu {
    NSString *menuBuilder = [[NSUserDefaults standardUserDefaults] stringForKey:kMenuItemFunctionIdentifier];
    
    if ([menuBuilder length] == 0) {
        menuBuilder = @"public.submenu";
    }
    
    if ([self.statusMenuManager respondsToSelector:@selector(testState)]) {
        NSObject<HITPluginProtocol> *observablePluginInstance = self.statusMenuManager;
        [observablePluginInstance removeObserver:self forKeyPath:@"testState" context:nil];
    }
    
    Class<HITPluginProtocol> SubMenuPlugin = [[HITPluginsManager sharedInstance] mainClassForPluginWithFunctionIdentifier:menuBuilder];
    self.statusMenuManager = [SubMenuPlugin newPlugInInstanceWithSettings:[[NSUserDefaults standardUserDefaults] dictionaryRepresentation]];
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
        int substate = 0;
        
        if ([self.statusMenuManager respondsToSelector:@selector(testState)]) {
            substate |= [self.statusMenuManager testState];
        }
        
        if (substate&HITPluginTestStateError) self.testState = HITPluginTestStateError;
        else if (substate&HITPluginTestStateWarning) self.testState = HITPluginTestStateWarning;
        else if (substate&HITPluginTestStateUnavailable) self.testState = HITPluginTestStateUnavailable;
        else if (substate&HITPluginTestStateOK) self.testState = HITPluginTestStateOK;
        else self.testState = HITPluginTestStateNone;
        
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "General state has changed for %lu.", (unsigned long)self.testState);
        
        [self updateStatusItem];
    }
}

@end
