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

#import <os/log.h>

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
                                         os_log_info(OS_LOG_DEFAULT, "Connection error during test.");
                                         os_log_debug(OS_LOG_DEFAULT, "%s", [[connectionError description] cStringUsingEncoding:NSUTF8StringEncoding]);
                                         
                                     } else {
                                         NSError *jsonError = nil;
                                         NSDictionary * cachetInfos = [NSJSONSerialization JSONObjectWithData:data
                                                                                                      options:0
                                                                                                        error:&jsonError];
                                         
                                         if (jsonError) {
                                             self.testState = HITPluginTestStateNone;
                                             os_log_info(OS_LOG_DEFAULT, "JSON decoding error.");
                                             os_log_debug(OS_LOG_DEFAULT, "%s", [[jsonError description] cStringUsingEncoding:NSUTF8StringEncoding]);
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
        os_log_error(OS_LOG_DEFAULT, "Impossible scenario, all groups' menu should have been created now!");
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
    os_log_info(OS_LOG_DEFAULT, "Sumerizing CachetHQ states");
    
    NSInteger worstState = 1;
    for (NSMenuItem *groupMenuItem in self.cachetHQMenu.itemArray) {
        NSInteger submenuWorstState = 1;
        
        os_log_debug(OS_LOG_DEFAULT, "Working on group menu %s", [groupMenuItem.title cStringUsingEncoding:NSUTF8StringEncoding]);
        
        for (NSMenuItem *serviceMenuItem in groupMenuItem.submenu.itemArray) {
            NSDictionary *serviceInfo = serviceMenuItem.representedObject;
            NSNumber *serviceStatus = [serviceInfo objectForKey:@"status"];
            
            NSInteger state = [serviceStatus integerValue];
            os_log_debug(OS_LOG_DEFAULT, "Working on group item %s with current state %ld", [serviceMenuItem.title cStringUsingEncoding:NSUTF8StringEncoding], state);

            
            if (state > submenuWorstState) {
                os_log_debug(OS_LOG_DEFAULT, "Evaluated item state is worst than previous one for this group");
                submenuWorstState = state;
            }
        }
        
        os_log_debug(OS_LOG_DEFAULT, "Updating group menu %s with state %ld", [groupMenuItem.title cStringUsingEncoding:NSUTF8StringEncoding], submenuWorstState);
        [self updateMenuItem:groupMenuItem withCachetState:submenuWorstState];

        if (submenuWorstState > worstState) {
            os_log_debug(OS_LOG_DEFAULT, "Evaluated group state is worst than previous one for the global state");
            worstState = submenuWorstState;
        }
    }
    os_log_debug(OS_LOG_DEFAULT, "Updating global menu %s with state %ld", [self.menuItem.title cStringUsingEncoding:NSUTF8StringEncoding], worstState);
    switch (worstState) {
        case 4:
            self.testState = HITPluginTestStateError;
            break;
        case 3:
        case 2:
            self.testState = HITPluginTestStateWarning;
            break;
        case 1:
            self.testState = HITPluginTestStateOK;
            break;
        default:
            self.testState = HITPluginTestStateNone;
            break;
    }
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
