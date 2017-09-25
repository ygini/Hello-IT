//
//  HITPADPass.m
//  ADPass
//
//  Created by Yoann Gini on 24/09/2017.
//  Copyright © 2017 Yoann Gini. All rights reserved.
//

#import "HITPADPass.h"
#import <OpenDirectory/OpenDirectory.h>

#define kHITPADPassExpiryTimeField @"msDS-UserPasswordExpiryTimeComputed"
#define kHITPADPassExpiryTimeKey @"public.ad.pass.expirySince1970"

#define kHITPADPassWillExpireFormat @"willExpireFormat"
#define kHITPADPassTooltip @"tooltip"
#define kHITPADPassDisabledTooltip @"disabledTooltip"

@interface HITPADPass ()

@property NSDate *passwordExpiracyDate;
@property BOOL lastADRequestSucceded;

@property NSString *localeTablePath;

@property NSString *defaultWillExpireFormat;
@property NSString *defaultTooltip;
@property NSString *defaultDisabledTooltip;

@property NSString *willExpireFormat;
@property NSString *tooltip;
@property NSString *disabledTooltip;

@end

@implementation HITPADPass

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _defaultWillExpireFormat = @"🔐 📆 %ld";
        _defaultTooltip = @"Delay before your password expire, change it before!";
        _defaultDisabledTooltip = @"Your IT infrastructure isn't available. Current info is based on the last recorded value.";
        
        _willExpireFormat = [settings objectForKey:kHITPADPassWillExpireFormat];
        _tooltip = [settings objectForKey:kHITPADPassTooltip];
        _disabledTooltip = [settings objectForKey:kHITPADPassDisabledTooltip];
        
        if ([_willExpireFormat length] == 0) {
            _willExpireFormat = _defaultWillExpireFormat;
        }
        
        if ([_tooltip length] == 0) {
            _tooltip = _defaultTooltip;
        }
        
        if ([_disabledTooltip length] == 0) {
            _disabledTooltip = _defaultDisabledTooltip;
        }
        
        _willExpireFormat = [[NSBundle bundleForClass:[self class]] localizedStringForKey:kHITPADPassWillExpireFormat value:_willExpireFormat table:nil];
        _tooltip = [[NSBundle bundleForClass:[self class]] localizedStringForKey:kHITPADPassTooltip value:_tooltip table:nil];
        _disabledTooltip = [[NSBundle bundleForClass:[self class]] localizedStringForKey:kHITPADPassDisabledTooltip value:_disabledTooltip table:nil];
    }
    return self;
}

- (void)mainAction:(id)sender {
    [[NSWorkspace sharedWorkspace] openFile:@"/System/Library/PreferencePanes/Accounts.prefPane"];
}

- (void)periodicAction:(NSTimer *)timer {
    [self getPasswordExpiryDate];
    [self updateTitle];
}

- (void)updateTitle {
    
    NSDateComponents *components = [[NSCalendar currentCalendar] components:NSCalendarUnitDay fromDate:[NSDate date] toDate:self.passwordExpiracyDate options:0];
    
    self.menuItem.title = [NSString stringWithFormat:self.willExpireFormat, (long)[components day]];
    self.menuItem.enabled = self.lastADRequestSucceded;
    
    self.menuItem.toolTip = self.lastADRequestSucceded ? self.tooltip : self.disabledTooltip;
}

- (void)getPasswordExpiryDate {
    NSError *error = nil;
    
    ODSession *searchSession = [ODSession sessionWithOptions:nil error:&error];
    
    ODNode *searchNode = [ODNode nodeWithSession:searchSession
                                            type:kODNodeTypeAuthentication
                                           error:&error];
    
    ODQuery *recordQuery = [ODQuery  queryWithNode:searchNode
                                    forRecordTypes:kODRecordTypeUsers
                                         attribute:kODAttributeTypeRecordName
                                         matchType:kODMatchEqualTo
                                       queryValues:NSUserName()
                                  returnAttributes:kHITPADPassExpiryTimeField
                                    maximumResults:0
                                             error:&error];
    
    NSArray *records = [recordQuery resultsAllowingPartial:NO error:&error];
    NSNumber *expiryTime = nil;
    for (ODRecord *record in records) {
        NSArray *values = [record valuesForAttribute:kHITPADPassExpiryTimeField error:&error];
        expiryTime = [values lastObject];
        
        if (expiryTime) {
            break;
        }
    }
    
    // Thank you Microsoft to use Jan 1, 1601 at 00:00 UTC as reference date…
    if (expiryTime) {
        NSDateComponents *adRefenreceDateComponents = [[NSDateComponents alloc] init];
        [adRefenreceDateComponents setDay:1];
        [adRefenreceDateComponents setMonth:1];
        [adRefenreceDateComponents setYear:1601];
        [adRefenreceDateComponents setEra:1];
        
        NSDate *adRefenreceDate = [[NSCalendar calendarWithIdentifier:NSCalendarIdentifierISO8601] dateFromComponents:adRefenreceDateComponents];
        NSTimeInterval expiryTimeInterval = [expiryTime integerValue] / 10000000.0;

        
        self.passwordExpiracyDate = [NSDate dateWithTimeInterval:expiryTimeInterval sinceDate:adRefenreceDate];
        self.lastADRequestSucceded = YES;
        
        [[NSUserDefaults standardUserDefaults] setInteger:[self.passwordExpiracyDate timeIntervalSince1970] forKey:kHITPADPassExpiryTimeKey];
    } else {
        NSInteger expirySince1970 = [[NSUserDefaults standardUserDefaults] integerForKey:kHITPADPassExpiryTimeKey];
        self.passwordExpiracyDate = [NSDate dateWithTimeIntervalSince1970:expirySince1970];
        self.lastADRequestSucceded = NO;
    }
}

@end
