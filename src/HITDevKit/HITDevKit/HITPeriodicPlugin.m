//
//  HITPeriodicPlugin.m
//  HITDevKit
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPeriodicPlugin.h"

@interface HITPeriodicPlugin ()
@property NSNumber *repeat;
@property NSTimer *cron;
@end

@implementation HITPeriodicPlugin

- (instancetype)initWithSettings:(NSDictionary *)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _repeat = [settings objectForKey:kHITPeriodicPluginRepeatKey];
        
        if ([_repeat intValue] > 0) {
            [self performSelector:@selector(setupCronJob)
                       withObject:nil
                       afterDelay:0];
        }
    }
    return self;
}

- (void)setupCronJob {
    _cron = [NSTimer scheduledTimerWithTimeInterval:[_repeat integerValue]
                                             target:self
                                           selector:@selector(periodicAction:)
                                           userInfo:nil
                                            repeats:YES];
    
    [_cron fire];
}

@end
