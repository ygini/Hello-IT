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
#define kMenuItemStatusBarIcon @"icon"

@interface AppDelegate ()

@property (weak) IBOutlet NSWindow *window;
@property (strong) NSStatusItem *statusItem;
@property (strong) IBOutlet NSMenu *statusMenu;
@property id<HITPluginProtocol> statusMenuManager;
@property NSMutableArray *pluginInstances;
@property Reachability *reachability;

@property (nonatomic) HITPluginTestState testState;

@property id notificationOjectForInterfaceTheme;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    self.pluginInstances = [NSMutableArray new];
    
    asl_add_log_file(NULL, STDERR_FILENO);
    
    // This is a sample configuration to allow Hello IT to run without any custom settings.
    // You don't have to edit this code and rebuild the apps to use it, you just have to
    // customize com.github.ygini.Hello-IT like indicated here on the documentation
    // https://github.com/ygini/Hello-IT/wiki/Preferences
    
    
    if ([[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"content"] count] == 0) {
        asl_log(NULL, NULL, ASL_LEVEL_WARNING, "No settings found in com.github.ygini.Hello-IT domain. Loading sample one.");
        
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{
                                                                  @"icon": @"default",
                                                                  @"title": @"Hello IT",
                                                                  @"content": @[
                                                                          @{@"functionIdentifier": @"public.title",
                                                                            @"settings": @{
                                                                                    @"title": @"Hello IT default content",
                                                                                    }
                                                                            },
                                                                          @{@"functionIdentifier": @"public.open.resource",
                                                                            @"settings": @{
                                                                                    @"title": @"Hello IT Documentation",
                                                                                    @"URL": @"https://github.com/ygini/Hello-IT/wiki"
                                                                                    }
                                                                            },
                                                                          @{@"functionIdentifier": @"public.open.resource",
                                                                            @"settings": @{
                                                                                    @"title": @"The page needed to deploy your custom content",
                                                                                    @"URL": @"https://github.com/ygini/Hello-IT/wiki/Preferences"
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

    
    [[HITPluginsManager sharedInstance] loadPluginsWithCompletionHandler:^(HITPluginsManager *pluginsManager) {
        [self loadMenu];
        
        self.reachability = [Reachability reachabilityForInternetConnection];
        [self.reachability startNotifier];
    }];
    
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
    [[NSNotificationCenter defaultCenter] removeObserver:self.notificationOjectForInterfaceTheme];
}

- (void)updateStatusItem {
    NSString *iconString = [[NSUserDefaults standardUserDefaults] stringForKey:kMenuItemStatusBarIcon];
    NSImage *icon = nil;
    
    if (iconString) {
        if ([iconString isEqualToString:@"default"]) {
            NSString *imageName = nil;
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
                imageName = [imageName stringByAppendingString:@"-dark"];
            }
            
            icon = [NSImage imageNamed:imageName];
            
        } else if ([iconString length] > 0) {
            NSMutableArray * pathComponents = [[iconString pathComponents] mutableCopy];
            
            NSString *filenameForDark = nil;
            NSMutableArray * pathComponentsForDark = nil;
            BOOL tryDark = NO;
            
            NSString *filename = [pathComponents lastObject];
            [pathComponents removeLastObject];
            
            NSString *osxMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"];
            
            if ([osxMode isEqualToString:@"Dark"]) {
                tryDark = YES;
                pathComponentsForDark = [pathComponents mutableCopy];
                filenameForDark = [@"dark-" stringByAppendingString:filename];
            }
            
            switch (self.testState) {
                case HITPluginTestStateError:
                    [pathComponents addObject:[@"error-" stringByAppendingString:filename]];
                    if (tryDark) {
                        [pathComponentsForDark addObject:[@"error-" stringByAppendingString:filenameForDark]];
                    }
                    break;
                case HITPluginTestStateUnavailable:
                    [pathComponents addObject:[@"unavailable-" stringByAppendingString:filename]];
                    if (tryDark) {
                        [pathComponentsForDark addObject:[@"unavailable-" stringByAppendingString:filenameForDark]];
                    }
                    break;
                case HITPluginTestStateWarning:
                    [pathComponents addObject:[@"warning-" stringByAppendingString:filename]];
                    if (tryDark) {
                        [pathComponentsForDark addObject:[@"warning-" stringByAppendingString:filenameForDark]];
                    }
                    break;
                case HITPluginTestStateOK:
                    [pathComponents addObject:[@"ok-" stringByAppendingString:filename]];
                    if (tryDark) {
                        [pathComponentsForDark addObject:[@"ok-" stringByAppendingString:filenameForDark]];
                    }
                    break;
                default:
                    if (tryDark) {
                        [pathComponentsForDark addObject:filenameForDark];
                    }
                    [pathComponents addObject:filename];
                    break;
            }
            
            NSString *finalPath = [pathComponents firstObject];
            [pathComponents removeObjectAtIndex:0];
            
            for (NSString *component in pathComponents) {
                finalPath = [finalPath stringByAppendingPathComponent:component];
            }
            
            NSString *finalPathForDark = [pathComponentsForDark firstObject];
            [pathComponentsForDark removeObjectAtIndex:0];
            
            for (NSString *component in pathComponentsForDark) {
                finalPathForDark = [finalPathForDark stringByAppendingPathComponent:component];
            }
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:finalPathForDark]) {
                icon = [[NSImage alloc] initWithContentsOfFile:finalPathForDark];
            }else if ([[NSFileManager defaultManager] fileExistsAtPath:finalPath]) {
                icon = [[NSImage alloc] initWithContentsOfFile:finalPath];
            } else if ([[NSFileManager defaultManager] fileExistsAtPath:iconString]) {
                icon = [[NSImage alloc] initWithContentsOfFile:iconString];
            }
        }
    }
    
    if (icon) {
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
    
    self.statusMenu = [[NSMenu alloc] init];
    
    NSStatusBar *bar = [NSStatusBar systemStatusBar];
    
    self.statusItem = [bar statusItemWithLength:NSVariableStatusItemLength];
    
    self.statusItem.highlightMode = YES;
    self.statusItem.menu = [self.statusMenuManager menuItem].submenu;
    
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
