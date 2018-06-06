//
//  CachetHQComponent.m
//  CachetHQ
//
//  Created by Yoann Gini on 05/06/2018.
//  Copyright © 2018 Yoann Gini (Open Source Project). All rights reserved.
//

#import "CachetHQComponent.h"

#define kCachetHQBaseURL @"baseURL"
#define kCachetHQSortScenario @"stateSortScenario"

#import <asl.h>

typedef NS_ENUM(NSInteger, HITPSubMenuSortScenario) {
    HITPSubMenuSortScenarioUnavailableWin = 0,
    HITPSubMenuSortScenarioOKWin
};

@interface CachetHQComponent () <NSMenuDelegate>
@property id<HITPluginsManagerProtocol> pluginsManager;
@property HITPSubMenuSortScenario stateSortScenario;
@property NSURL *componentsAPI;
@property NSMutableDictionary *menuItemPerServiceKey;
@property NSMutableDictionary *menuItemPerServiceGroupKey;
@property NSMutableDictionary *submenuPerServiceGroupKey;
@property NSMenu *cachetHQMenu;
@end


@implementation CachetHQComponent

+ (id<HITPluginProtocol>)newPlugInInstanceWithSettings:(NSDictionary*)settings {
    id instance = [[self alloc] initWithSettings:settings];
    return instance;
}

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _menuItemPerServiceKey = [NSMutableDictionary new];
        _menuItemPerServiceGroupKey = [NSMutableDictionary new];
        _submenuPerServiceGroupKey = [NSMutableDictionary new];
        _componentsAPI = [[NSURL URLWithString:[settings objectForKey:kCachetHQBaseURL]] URLByAppendingPathComponent:@"/api/v1/components/groups"];
        
        NSNumber *selectedScenario = [settings objectForKey:kCachetHQSortScenario];
        if (selectedScenario) {
            _stateSortScenario = [selectedScenario integerValue];
        } else {
            _stateSortScenario = HITPSubMenuSortScenarioUnavailableWin;
        }
    }
    return self;
}

-(NSMenuItem *)prepareNewMenuItem {
    NSMenuItem *menuItem = [super prepareNewMenuItem];
    menuItem.action = NULL;
    menuItem.target = nil;
    
    _cachetHQMenu = [[NSMenu alloc] init];
    _cachetHQMenu.delegate = self;
    
    menuItem.submenu = _cachetHQMenu;
    return menuItem;
}

- (void)periodicAction:(NSTimer *)timer {
    [self reloadStateAtPage:1];
}

- (void)reloadStateAtPage:(NSInteger)requestedPage {
    NSURLComponents *urlComponents = [NSURLComponents componentsWithURL:self.componentsAPI resolvingAgainstBaseURL:YES];
    
    urlComponents.queryItems = @[
                                 [NSURLQueryItem queryItemWithName:@"sort" value:@"id"],
                                 [NSURLQueryItem queryItemWithName:@"order" value:@"desc"],
#ifdef DEBUG
                                 // Here to ensure during debug that pagination is working well.
                                 [NSURLQueryItem queryItemWithName:@"per_page" value:@"3"],
#endif

                                 [NSURLQueryItem queryItemWithName:@"page" value:[NSString stringWithFormat:@"%ld", (long)requestedPage]]
                                 ];
    
    [[[NSURLSession sharedSession] dataTaskWithURL:[urlComponents URL]
                                 completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable connectionError) {
                                     if (connectionError) {
                                         self.testState = HITPluginTestStateNone;
                                         asl_log(NULL, NULL, ASL_LEVEL_INFO, "Connection error during test.");
                                         asl_log(NULL, NULL, ASL_LEVEL_DEBUG, "%s", [[connectionError description] cStringUsingEncoding:NSUTF8StringEncoding]);
                                         
                                     } else {
                                         NSError *jsonError = nil;
                                         NSDictionary * cachetInfos = [NSJSONSerialization JSONObjectWithData:data
                                                                                                      options:0
                                                                                                        error:&jsonError];
                                         
                                         if (jsonError) {
                                             self.testState = HITPluginTestStateNone;
                                             asl_log(NULL, NULL, ASL_LEVEL_INFO, "JSON decoding error.");
                                             asl_log(NULL, NULL, ASL_LEVEL_DEBUG, "%s", [[jsonError description] cStringUsingEncoding:NSUTF8StringEncoding]);
                                         } else {
                                             
                                             NSInteger totalPages = [[cachetInfos valueForKeyPath:@"meta.pagination.total_pages"] integerValue];
                                             
                                             
                                             for (NSDictionary *serviceGroup in [cachetInfos objectForKey:@"data"]) {
                                                 NSNumber *serviceGroupID = [serviceGroup objectForKey:@"id"];
                                                 [self updateServiceGroup:[serviceGroupID stringValue] withInfos:serviceGroup];
                                             }
                                             
                                             [self updateSumarizedServicesState];
                                             
                                             if (requestedPage < totalPages) {
                                                 dispatch_async(dispatch_get_main_queue(), ^{
                                                     [self reloadStateAtPage:requestedPage+1];
                                                 });
                                             }
                                         }
                                     }
                                 }] resume];
}

- (void)updateServiceGroup:(NSString*)serviceGroupKey withInfos:(NSDictionary*)infos {
    NSString *serviceGroupName = [infos objectForKey:@"name"];
    
    NSMenu *groupSubmenu = nil;
    @synchronized(_submenuPerServiceGroupKey) {
        groupSubmenu = [self.submenuPerServiceGroupKey objectForKey:serviceGroupKey];
        if (!groupSubmenu) {
            groupSubmenu = [NSMenu new];
            
            [self.submenuPerServiceGroupKey setObject:groupSubmenu forKey:serviceGroupKey];
            
            NSMenuItem * menuItem = nil;
            @synchronized(_menuItemPerServiceGroupKey) {
                menuItem = [self.menuItemPerServiceGroupKey objectForKey:serviceGroupKey];
                if (!menuItem) {
                    menuItem = [[NSMenuItem alloc] initWithTitle:serviceGroupName
                                                          action:NULL
                                                   keyEquivalent:@""];
                    
                    [self.menuItemPerServiceKey setObject:menuItem forKey:serviceGroupKey];
                    [self.cachetHQMenu addItem:menuItem];
                }
            }
            
            menuItem.submenu = groupSubmenu;
        }
    }
        
    for (NSDictionary *serviceState in [infos objectForKey:@"enabled_components"]) {
        NSNumber *serviceID = [serviceState objectForKey:@"id"];
        [self updateService:[NSString stringWithFormat:@"%@-%@", serviceGroupKey, serviceID] withInfos:serviceState];
    }
    

}

- (void)updateService:(NSString*)serviceKey withInfos:(NSDictionary*)infos {
    NSString *serviceName = [infos objectForKey:@"name"];
    NSString *serviceDescription = [infos objectForKey:@"description"];
    NSNumber *serviceStatus = [infos objectForKey:@"status"];
    NSString *serviceGroupKey = [[infos objectForKey:@"group_id"] stringValue];
    
    NSMenu *groupSubmenu = nil;
    @synchronized(_submenuPerServiceGroupKey) {
        groupSubmenu = [self.submenuPerServiceGroupKey objectForKey:serviceGroupKey];
    }
    
    if (!groupSubmenu) {
        asl_log(NULL, NULL, ASL_LEVEL_ERR, "Impossible scenario, all groups' menu should have been created now!");
    } else {
        NSMenuItem *menuItem = nil;
        @synchronized(_menuItemPerServiceKey) {
            menuItem = [self.menuItemPerServiceKey objectForKey:serviceKey];
            if (!menuItem) {
                menuItem = [[NSMenuItem alloc] initWithTitle:serviceName
                                                      action:@selector(userActionOnServiceItem:)
                                               keyEquivalent:@""];
                menuItem.target = self;
                
                [self.menuItemPerServiceKey setObject:menuItem forKey:serviceKey];
                [groupSubmenu addItem:menuItem];
            }
        }
        
        menuItem.title = serviceName;
        menuItem.toolTip = serviceDescription;
        menuItem.representedObject = infos;
        
        [self updateMenuItem:menuItem withCachetState:[serviceStatus integerValue]];
    }
}

- (void)updateSumarizedServicesState {
    NSInteger worstState = 1;
    for (NSMenuItem *groupMenuItem in self.cachetHQMenu.itemArray) {
        NSInteger submenuWorstState = 1;
        
        for (NSMenuItem *serviceMenuItem in groupMenuItem.menu.itemArray) {
            NSDictionary *serviceInfo = serviceMenuItem.representedObject;
            NSNumber *serviceStatus = [serviceInfo objectForKey:@"status"];
            
            NSInteger state = [serviceStatus integerValue];
            
            if (state > submenuWorstState) {
                submenuWorstState = state;
            }

        }
        
        [self updateMenuItem:groupMenuItem withCachetState:submenuWorstState];

        if (submenuWorstState > worstState) {
            worstState = submenuWorstState;
        }
    }
    
    [self updateMenuItem:self.menuItem withCachetState:worstState];
}

- (void)updateMenuItem:(NSMenuItem*)menuItem withCachetState:(NSInteger)state {
    switch (state) {
        case 4:
            menuItem.image = [[NSImage alloc] initWithContentsOfFile:[[NSBundle bundleWithIdentifier:@"com.github.ygini.HITDevKit"] pathForResource:@"Error"
                                                                                                                                             ofType:@"tiff"]];
            break;
        case 3:
        case 2:
            menuItem.image = [[NSImage alloc] initWithContentsOfFile:[[NSBundle bundleWithIdentifier:@"com.github.ygini.HITDevKit"] pathForResource:@"Warning"
                                                                                                                                             ofType:@"tiff"]];
            break;
        case 1:
            menuItem.image = [[NSImage alloc] initWithContentsOfFile:[[NSBundle bundleWithIdentifier:@"com.github.ygini.HITDevKit"] pathForResource:@"OK"
                                                                                                                                             ofType:@"tiff"]];
            break;
        default:
            menuItem.image = nil;
            break;
    }
}

- (void)userActionOnServiceItem:(NSMenuItem*)menuItem {
    NSDictionary *infos = menuItem.representedObject;
    NSURL *serviceLink = [NSURL URLWithString:[infos objectForKey:@"link"]];

    if (serviceLink) {
        [[NSWorkspace sharedWorkspace] openURL:serviceLink];
    }
}

#pragma mark - NSMenuDelegate

- (void)menuWillOpen:(NSMenu *)menu {
}

- (void)menuDidClose:(NSMenu *)menu {
}


@end
