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
        if ([settings.allKeys containsObject:kHITPeriodicPluginRepeatKey]) {
            _repeat = [settings objectForKey:kHITPeriodicPluginRepeatKey];
        } else {
            _repeat = @60;
        }
        
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
                                           selector:@selector(runPeriodicAction:)
                                           userInfo:nil
                                            repeats:YES];
    
    [_cron fire];
}

- (void)stopAndPrepareForRelease {
    [_cron invalidate];
    [super stopAndPrepareForRelease];
}

- (void)runPeriodicAction:(NSTimer*)timer {
    if (self.allowedToRun) {
        [self periodicAction:timer];
    }
}

@end
