//
//  HIPluginsManager.m
//  Hello IT
//
//  Created by Yoann Gini on 11/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPluginsManager.h"

#define kHITPPlugInsFolder @"PlugIns"

#define kHITPFunctionIdentifier @"HITPFunctionIdentifier"

#import "AppDelegate.h"
#import "Reachability.h"
#import <os/log.h>

@interface HITPluginsManager () <NSUserNotificationCenterDelegate>
@property NSDictionary *pluginURLPerFunctionIdentifier;
@property NSMutableDictionary *loadedPluginsPerFunctionIdentifier;
@property NSMutableArray *networkRelatedPluginInstances;
@property NSMutableDictionary *pluginsAwaitingForNotifications;
@end

@implementation HITPluginsManager

#pragma mark - Initialization methods

+ (instancetype)sharedInstance {
    static id sharedInstanceHIPluginsManager = nil;
    static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		sharedInstanceHIPluginsManager = [self new];
	});
    return sharedInstanceHIPluginsManager;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _loadedPluginsPerFunctionIdentifier = [NSMutableDictionary new];
        _pluginsAwaitingForNotifications = [NSMutableDictionary new];
        _networkRelatedPluginInstances = [NSMutableArray new];
        
        [NSUserNotificationCenter defaultUserNotificationCenter].delegate = self;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChangedNotification:) name:kReachabilityChangedNotification object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kReachabilityChangedNotification object:nil];
}

- (void)loadPluginsWithCompletionHandler:(void(^)(HITPluginsManager *pluginsManager))handler {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        os_log_info(OS_LOG_DEFAULT, "Start loading plugins");
        
        NSMutableDictionary * plugins = [NSMutableDictionary new];
        for (NSURL *pluginsFolderURL in [self pluginsURLs]) {
            os_log_info(OS_LOG_DEFAULT, "Looking for plugins inside %s", [[pluginsFolderURL path] cStringUsingEncoding:NSUTF8StringEncoding]);
            NSError *error = nil;
            
            NSArray *folderContent = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:pluginsFolderURL
                                                                   includingPropertiesForKeys:nil
                                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                        error:&error];
            
            if (error) {
                os_log_error(OS_LOG_DEFAULT, "%s", [[NSString stringWithFormat:@"Error when trying to load plugins from %@:\n%@", pluginsFolderURL, [error localizedDescription]] cStringUsingEncoding:NSUTF8StringEncoding]);
            } else {
                for (NSURL *pluginURL in folderContent) {
                    if ([[pluginURL pathExtension] isEqualToString:@"hitp"]
                        && [pluginURL isFileURL]) {
                        
                        NSString *functionIdentifier = [[[NSBundle bundleWithURL:pluginURL] infoDictionary] objectForKey:kHITPFunctionIdentifier];
                        
                        if ([functionIdentifier length] > 0) {
                            os_log_debug(OS_LOG_DEFAULT, "Function identifier %s referenced with plugin at path %s", [functionIdentifier cStringUsingEncoding:NSUTF8StringEncoding], [[pluginURL path] cStringUsingEncoding:NSUTF8StringEncoding]);
                            [plugins setObject:pluginURL forKey:functionIdentifier];
                        } else {
                            os_log_error(OS_LOG_DEFAULT, "Plugin found without function identifier, plugin not loaded: %s", [[pluginURL path] cStringUsingEncoding:NSUTF8StringEncoding]);
                        }
                        
                    } else {
                        os_log_info(OS_LOG_DEFAULT, "Item found in plugin directory without plugin extention, skipping: %s", [[pluginURL path] cStringUsingEncoding:NSUTF8StringEncoding]);
                    }
                }
            }
        }
        
        self.pluginURLPerFunctionIdentifier = [NSDictionary dictionaryWithDictionary:plugins];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            os_log_info(OS_LOG_DEFAULT, "Done loading plugins");
            handler(self);
        });
    });
}

- (NSArray*)pluginsURLs {
    NSError *error = nil;
    NSURL *URL = nil;
    
    NSMutableArray *URLs = [NSMutableArray new];
    
    // Plugins directory inside the application
    URL = [[NSBundle mainBundle] builtInPlugInsURL];
    if ([self directoryUsableAtURL:URL]) {
        [URLs addObject:URL];
    } else {
        os_log_info(OS_LOG_DEFAULT, "Plugin path %s not usable on this system", [[URL path] cStringUsingEncoding:NSUTF8StringEncoding]);
    }
    
    // Plugins directory for current system (/Library)
    URL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                 inDomain:NSLocalDomainMask
                                        appropriateForURL:nil
                                                   create:NO
                                                    error:&error];
    if (error) {
        os_log_error(OS_LOG_DEFAULT, "Error when trying to access plugin directory in /Library:\n%s", [[error localizedDescription] cStringUsingEncoding:NSUTF8StringEncoding]);
    } else {
        URL = [[URL URLByAppendingPathComponent:[[[NSBundle mainBundle] bundleIdentifier] lowercaseString]] URLByAppendingPathComponent:kHITPPlugInsFolder];
        if ([self directoryUsableAtURL:URL]) {
            [URLs addObject:URL];
        } else {
            os_log_info(OS_LOG_DEFAULT, "Plugin path %s not usable on this system", [[URL path] cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
    
    // Plugins directory for current user (~/Library)
    URL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                 inDomain:NSUserDomainMask
                                        appropriateForURL:nil
                                                   create:NO
                                                    error:&error];
    if (error) {
        os_log_error(OS_LOG_DEFAULT, "Error when trying to access plugin directory in ~/Library:\n%s", [[error localizedDescription] cStringUsingEncoding:NSUTF8StringEncoding]);
    } else {
        URL = [[URL URLByAppendingPathComponent:[[[NSBundle mainBundle] bundleIdentifier] lowercaseString]] URLByAppendingPathComponent:kHITPPlugInsFolder];
        if ([self directoryUsableAtURL:URL]) {
            [URLs addObject:URL];
        } else {
            os_log_info(OS_LOG_DEFAULT, "Plugin path %s not usable on this system", [[URL path] cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
    
    return [NSArray arrayWithArray:URLs];
}

#pragma mark - Bundle handling

- (Class<HITPluginProtocol>)mainClassForPluginWithFunctionIdentifier:(NSString*)functionIdentifier {
    NSBundle *plugin = [self.loadedPluginsPerFunctionIdentifier objectForKey:functionIdentifier];
    if (!plugin) {
        NSURL *pluginURL = [self.pluginURLPerFunctionIdentifier objectForKey:functionIdentifier];
        
        if ([pluginURL isFileURL]) {
            plugin = [NSBundle bundleWithURL:pluginURL];
            [self.loadedPluginsPerFunctionIdentifier setObject:plugin forKey:functionIdentifier];
        } else {
            os_log_error(OS_LOG_DEFAULT, "Plugin path returned for %s isn't a file URL: %s", [functionIdentifier cStringUsingEncoding:NSUTF8StringEncoding], [[pluginURL absoluteString] cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
    
    if (plugin) {
        NSError *error = nil;
        BOOL success = [plugin loadAndReturnError:&error];
        
        if (success) {
            return [plugin principalClass];
        } else {
            os_log_error(OS_LOG_DEFAULT, "Error when loading plugin for %s: %s", [functionIdentifier cStringUsingEncoding:NSUTF8StringEncoding], [[error description] cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
    
    return Nil;
}

- (void)registerPluginInstanceAsNetworkRelated:(id<HITPluginProtocol>)plugin {
    [self.networkRelatedPluginInstances addObject:plugin];
    
    [plugin generalNetworkStateUpdate:[((AppDelegate*)[NSApplication sharedApplication].delegate).reachability currentReachabilityStatus] != NotReachable];
}

#pragma mark - Network related plugins management

- (void)reachabilityChangedNotification:(NSNotification*)notification {
    if ([notification.object isKindOfClass:[Reachability class]]) {
        Reachability *reachability = notification.object;
        
        os_log_info(OS_LOG_DEFAULT, "Reachability state changed for system");

        for (id<HITPluginProtocol> plugin in self.networkRelatedPluginInstances) {
            BOOL state = [reachability currentReachabilityStatus] != NotReachable;
            
            if ([plugin respondsToSelector:@selector(generalNetworkStateUpdate:)]) {
                [plugin generalNetworkStateUpdate:state];
            }
        }
    }
}

#pragma mark - Toolbox

- (BOOL)directoryUsableAtURL:(NSURL*)URL {
    if (!URL) return NO;
    
    BOOL isFolder = NO;
    BOOL pathExist = NO;

    if ([URL isFileURL]) {
        pathExist = [[NSFileManager defaultManager] fileExistsAtPath:[URL path] isDirectory:&isFolder];
    }
    
    return pathExist && isFolder;
}

#pragma mark - Notifications Management

- (void)sendNotificationWithTitle:(NSString*)title andMessage:(NSString*)message from:(id<HITPluginProtocol>)sender {
    os_log_info(OS_LOG_DEFAULT, "Simple notification requested");
    NSUserNotification *notification = [NSUserNotification new];
    
    notification.title = title;
    notification.hasActionButton = NO;
    notification.informativeText = message;
    
    [self sendNotification:notification from:sender];
}

- (void)sendNotification:(NSUserNotification*)notification from:(id<HITPluginProtocol>)sender {
    os_log_info(OS_LOG_DEFAULT, "Notification sent");
    NSString *senderID = [[self.pluginsAwaitingForNotifications keysOfEntriesPassingTest:^BOOL(id  _Nonnull key, id  _Nonnull obj, BOOL * _Nonnull stop) {
        if (obj == sender) {
            *stop = YES;
            return YES;
        }
        return NO;
    }] anyObject];
    
    if (!senderID) {
        senderID = [[NSUUID UUID] UUIDString];
        [self.pluginsAwaitingForNotifications setObject:sender forKey:senderID];
    }

    NSMutableDictionary* userInfo = [NSMutableDictionary new];
    if (notification.userInfo) {
        [userInfo setDictionary:notification.userInfo];
    }
    [userInfo setObject:senderID forKey:@"senderID"];
    
    notification.userInfo = userInfo;
    
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification {
    NSString* senderID = [notification.userInfo objectForKey:@"senderID"];
    if ([senderID length] > 0) {
        id<HITPluginProtocol> sender = [self.pluginsAwaitingForNotifications objectForKey:senderID];
        if ([sender respondsToSelector:@selector(actionFromNotification:)]) {
            [sender actionFromNotification:notification];
        }
    }
    [center removeDeliveredNotification:notification];
}

-(BOOL)userNotificationCenter:(NSUserNotificationCenter *)center shouldPresentNotification:(nonnull NSUserNotification *)notification {
    return YES;
}

@end
