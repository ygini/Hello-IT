//
//  HITPOpenApplication.m
//  OpenApplication
//
//  Created by Yoann Gini on 16/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPOpenApplication.h"

#define kHITPOpenApplicationTitle @"title"
#define kHITPOpenApplicationName @"app"
#define kHITPOpenApplicationFileToOpen @"file"

@interface HITPOpenApplication ()
@property NSString *title;
@property NSString *application;
@property NSString *file;
@end

@implementation HITPOpenApplication
+ (id<HITPluginProtocol>)newPlugInInstanceWithSettings:(NSDictionary*)settings {
    id instance = [[self alloc] initWithSettings:settings];
    return instance;
}

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super init];
    if (self) {
        _title = [settings objectForKey:kHITPOpenApplicationTitle];
        _application = [settings objectForKey:kHITPOpenApplicationName];
        _file = [[settings objectForKey:kHITPOpenApplicationFileToOpen] stringByExpandingTildeInPath];
    }
    return self;
}

- (NSMenuItem*)menuItem {
    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:self.title
                                                      action:@selector(openRessource:)
                                               keyEquivalent:@""];
    
    menuItem.target = self;
    
    return menuItem;
}

- (void)openRessource:(id)sender {
    [[NSWorkspace sharedWorkspace] openFile:self.file withApplication:self.application andDeactivate:YES];
}

@end
