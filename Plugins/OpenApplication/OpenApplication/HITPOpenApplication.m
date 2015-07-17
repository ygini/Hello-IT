//
//  HITPOpenApplication.m
//  OpenApplication
//
//  Created by Yoann Gini on 16/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPOpenApplication.h"

#define kHITPOpenApplicationName @"app"
#define kHITPOpenApplicationFileToOpen @"file"

@interface HITPOpenApplication ()
@property NSString *application;
@property NSString *file;
@end

@implementation HITPOpenApplication

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _application = [settings objectForKey:kHITPOpenApplicationName];
        _file = [[settings objectForKey:kHITPOpenApplicationFileToOpen] stringByExpandingTildeInPath];
    }
    return self;
}

- (void)mainAction:(id)sender {
    [[NSWorkspace sharedWorkspace] openFile:self.file withApplication:self.application andDeactivate:YES];
}

@end
