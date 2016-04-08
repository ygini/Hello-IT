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

#import "Reachability.h"
#import <asl.h>

@interface HITPluginsManager ()
@property NSDictionary *pluginURLPerFunctionIdentifier;
@property NSMutableDictionary *loadedPluginsPerFunctionIdentifier;
@property NSMutableArray *networkRelatedPluginInstances;
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
        _networkRelatedPluginInstances = [NSMutableArray new];
                
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(reachabilityChangedNotification:) name:kReachabilityChangedNotification object:nil];
    }
    return self;
}

- (void)loadPluginsWithCompletionHandler:(void(^)(HITPluginsManager *pluginsManager))handler {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "Start loading plugins");
        
        NSMutableDictionary * plugins = [NSMutableDictionary new];
        for (NSURL *pluginsFolderURL in [self pluginsURLs]) {
            asl_log(NULL, NULL, ASL_LEVEL_INFO, "Looking for plugins inside %s", [[pluginsFolderURL path] cStringUsingEncoding:NSUTF8StringEncoding]);
            NSError *error = nil;
            
            NSArray *folderContent = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:pluginsFolderURL
                                                                   includingPropertiesForKeys:nil
                                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                        error:&error];
            
            if (error) {
                asl_log(NULL, NULL, ASL_LEVEL_ERR, "%s", [[NSString stringWithFormat:@"Error when trying to load plugins from %@:\n%@", pluginsFolderURL, [error localizedDescription]] cStringUsingEncoding:NSUTF8StringEncoding]);
            } else {
                for (NSURL *pluginURL in folderContent) {
                    if ([[pluginURL pathExtension] isEqualToString:@"hitp"]
                        && [pluginURL isFileURL]) {
                        
                        NSString *functionIdentifier = [[[NSBundle bundleWithURL:pluginURL] infoDictionary] objectForKey:kHITPFunctionIdentifier];
                        
                        if ([functionIdentifier length] > 0) {
                            asl_log(NULL, NULL, ASL_LEVEL_DEBUG, "Function identifier %s referenced with plugin at path %s", [functionIdentifier cStringUsingEncoding:NSUTF8StringEncoding], [[pluginURL path] cStringUsingEncoding:NSUTF8StringEncoding]);
                            [plugins setObject:pluginURL forKey:functionIdentifier];
                        } else {
                            asl_log(NULL, NULL, ASL_LEVEL_ERR, "Plugin found without function identifier, plugin not loaded: %s", [[pluginURL path] cStringUsingEncoding:NSUTF8StringEncoding]);
                        }
                        
                    } else {
                        asl_log(NULL, NULL, ASL_LEVEL_INFO, "Item found in plugin directory without plugin extention, skipping: %s", [[pluginURL path] cStringUsingEncoding:NSUTF8StringEncoding]);
                    }
                }
            }
        }
        
        self.pluginURLPerFunctionIdentifier = [NSDictionary dictionaryWithDictionary:plugins];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            asl_log(NULL, NULL, ASL_LEVEL_INFO, "Done loading plugins");
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
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "Plugin path %s not usable on this system", [[URL path] cStringUsingEncoding:NSUTF8StringEncoding]);
    }
    
    // Plugins directory for current system (/Library)
    URL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                 inDomain:NSLocalDomainMask
                                        appropriateForURL:nil
                                                   create:NO
                                                    error:&error];
    if (error) {
        asl_log(NULL, NULL, ASL_LEVEL_ERR, "Error when trying to access plugin directory in /Library:\n%s", [[error localizedDescription] cStringUsingEncoding:NSUTF8StringEncoding]);
    } else {
        URL = [[URL URLByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]] URLByAppendingPathComponent:kHITPPlugInsFolder];
        if ([self directoryUsableAtURL:URL]) {
            [URLs addObject:URL];
        } else {
            asl_log(NULL, NULL, ASL_LEVEL_INFO, "Plugin path %s not usable on this system", [[URL path] cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
    
    // Plugins directory for current user (~/Library)
    URL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                 inDomain:NSUserDomainMask
                                        appropriateForURL:nil
                                                   create:NO
                                                    error:&error];
    if (error) {
        asl_log(NULL, NULL, ASL_LEVEL_ERR, "Error when trying to access plugin directory in ~/Library:\n%s", [[error localizedDescription] cStringUsingEncoding:NSUTF8StringEncoding]);
    } else {
        URL = [[URL URLByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]] URLByAppendingPathComponent:kHITPPlugInsFolder];
        if ([self directoryUsableAtURL:URL]) {
            [URLs addObject:URL];
        } else {
            asl_log(NULL, NULL, ASL_LEVEL_INFO, "Plugin path %s not usable on this system", [[URL path] cStringUsingEncoding:NSUTF8StringEncoding]);
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
            asl_log(NULL, NULL, ASL_LEVEL_ERR, "Plugin path returned for %s isn't a file URL: %s", [functionIdentifier cStringUsingEncoding:NSUTF8StringEncoding], [[pluginURL absoluteString] cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
    
    if (plugin) {
        NSError *error = nil;
        BOOL success = [plugin loadAndReturnError:&error];
        
        if (success) {
            return [plugin principalClass];
        } else {
            asl_log(NULL, NULL, ASL_LEVEL_ERR, "Error when loading plugin for %s: %s", [functionIdentifier cStringUsingEncoding:NSUTF8StringEncoding], [[error description] cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
    
    return Nil;
}

- (void)registerPluginInstanceAsNetworkRelated:(id<HITPluginProtocol>)plugin {
    [self.networkRelatedPluginInstances addObject:plugin];
}

#pragma mark - Network related plugins management

- (void)reachabilityChangedNotification:(NSNotification*)notification {
    if ([notification.object isKindOfClass:[Reachability class]]) {
        Reachability *reachability = notification.object;
        
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "Reachability state changed for system");

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


@end
