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

@interface HITPluginsManager ()
@property NSDictionary *pluginURLPerFunctionIdentifier;
@property NSMutableDictionary *loadedPluginsPerFunctionIdentifier;
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
    }
    return self;
}

- (void)loadPluginsWithCompletionHandler:(void(^)(HITPluginsManager *pluginsManager))handler {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        NSMutableDictionary * plugins = [NSMutableDictionary new];
        for (NSURL *pluginsFolderURL in [self pluginsURLs]) {
            NSError *error = nil;
            
            NSArray *folderContent = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:pluginsFolderURL
                                                                   includingPropertiesForKeys:nil
                                                                                      options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                        error:&error];
            if (error) {
                NSLog(@"Error when trying to load plugins from %@\nError description: %@", pluginsFolderURL, [error localizedDescription]);
            }
            
            for (NSURL *pluginURL in folderContent) {
                if ([[pluginURL pathExtension] isEqualToString:@"hitp"]
                    && [pluginURL isFileURL]) {
                    
                    NSString *functionIdentifier = [[[NSBundle bundleWithURL:pluginURL] infoDictionary] objectForKey:kHITPFunctionIdentifier];
                    [plugins setObject:pluginURL forKey:functionIdentifier];
                } else {
                    NSLog(@"Unable to reference plugin at path: %@", pluginURL);
                }
            }
        }
        
        self.pluginURLPerFunctionIdentifier = [NSDictionary dictionaryWithDictionary:plugins];
        
        dispatch_async(dispatch_get_main_queue(), ^{
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
    if ([self directoryUsableAtURL:URL]) [URLs addObject:URL];
    
    // Plugins directory for current system (/Library)
    URL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                 inDomain:NSLocalDomainMask
                                        appropriateForURL:nil
                                                   create:NO
                                                    error:&error];
    if (error) {
        NSLog(@"Error when trying to build URL for directory /Library\nError description: %@", [error localizedDescription]);
    } else {
        URL = [[URL URLByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]] URLByAppendingPathComponent:kHITPPlugInsFolder];
        if ([self directoryUsableAtURL:URL]) [URLs addObject:URL];
    }
    
    // Plugins directory for current user (~/Library)
    URL = [[NSFileManager defaultManager] URLForDirectory:NSApplicationSupportDirectory
                                                 inDomain:NSUserDomainMask
                                        appropriateForURL:nil
                                                   create:NO
                                                    error:&error];
    if (error) {
        NSLog(@"Error when trying to build URL for directory ~/Library\nError description: %@", [error localizedDescription]);
    } else {
        URL = [[URL URLByAppendingPathComponent:[[NSBundle mainBundle] bundleIdentifier]] URLByAppendingPathComponent:kHITPPlugInsFolder];
        if ([self directoryUsableAtURL:URL]) [URLs addObject:URL];
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
            NSLog(@"Plugin path returned for %@ isn't a file URL: %@", functionIdentifier, pluginURL);
        }
    }
    
    if (plugin) {
        NSError *error = nil;
        BOOL success = [plugin loadAndReturnError:&error];
        
        if (success) {
            return [plugin principalClass];
        } else {
            NSLog(@"Error when loading plugin: %@", [error localizedDescription]);
        }
    }
    
    return Nil;
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
