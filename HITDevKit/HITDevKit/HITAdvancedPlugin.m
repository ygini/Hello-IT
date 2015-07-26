//
//  HITAdvancedPlugin.m
//  HITDevKit
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITAdvancedPlugin.h"

@interface HITAdvancedPlugin () {
    HITPluginTestState _testState;
}

@end

@implementation HITAdvancedPlugin

@dynamic testState;

- (void)updateMenuItemState {
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (self.testState) {
            case HITPluginTestStateError:
                self.menuItem.image = [[NSImage alloc] initWithContentsOfFile:[[NSBundle bundleWithIdentifier:@"com.github.ygini.HITDevKit"] pathForResource:@"Error"
                                                                                                                                                      ofType:@"tiff"]];
                break;
            case HITPluginTestStateOK:
                self.menuItem.image = [[NSImage alloc] initWithContentsOfFile:[[NSBundle bundleWithIdentifier:@"com.github.ygini.HITDevKit"] pathForResource:@"OK"
                                                                                                                                                      ofType:@"tiff"]];
                break;
            case HITPluginTestStateWarning:
                self.menuItem.image = [[NSImage alloc] initWithContentsOfFile:[[NSBundle bundleWithIdentifier:@"com.github.ygini.HITDevKit"] pathForResource:@"Warning"
                                                                                                                                                      ofType:@"tiff"]];
                break;
            case HITPluginTestStateUnavailable:
                break;
            case HITPluginTestStateNone:
            default:
                self.menuItem.image = nil;
                break;
        }
    });
}

-(HITPluginTestState)testState {
    return _testState;
}

-(void)setTestState:(HITPluginTestState)testState {
    _testState = testState;
    [self updateMenuItemState];
}

@end
