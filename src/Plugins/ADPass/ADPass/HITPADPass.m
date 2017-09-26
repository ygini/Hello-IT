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
#define kHITPADPassLastNotifKey @"public.ad.pass.lastNotification"

#define kHITPADPassWillExpireFormat @"willExpireFormat"
#define kHITPADPassTooltip @"tooltip"
#define kHITPADPassOfflineTooltip @"offlineTooltip"

#define kHITPADPassNotifTitle @"notificationTitle"
#define kHITPADPassNotifMessageFormat @"notificationMessageFormat"
#define kHITPADPassNotifOfflineMessageFormat @"notificationOfflineMessageFormat"

#define kHITPADPassAlertXDaysBefore @"alertXDaysBefore"

@interface HITPADPass ()

@property NSDate *passwordExpiryDate;
@property BOOL lastADRequestSucceded;

@property NSString *localeTablePath;

@property NSString *willExpireFormat;
@property NSString *tooltip;
@property NSString *offlineTooltip;

@property NSString *notificationTitle;
@property NSString *notificationMessageFormat;
@property NSString *notificationOfflineMessageFormat;

@property NSInteger alertXDaysBefore;

@end

@implementation HITPADPass

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _alertXDaysBefore = [[settings objectForKey:kHITPADPassAlertXDaysBefore] integerValue];
        
        if (_alertXDaysBefore == 0) {
            _alertXDaysBefore = 15;
        }
        
        NSString *defaultWillExpireFormat = @"🔐 📆 %ld";
        NSString *defaultTooltip = @"Delay before your password expire, change it before!";
        NSString *defaultOfflineTooltip = @"Your IT infrastructure isn't available. Current info is based on the last recorded value.";
        
        _willExpireFormat = [settings objectForKey:kHITPADPassWillExpireFormat];
        _tooltip = [settings objectForKey:kHITPADPassTooltip];
        _offlineTooltip = [settings objectForKey:kHITPADPassOfflineTooltip];
        
        if ([_willExpireFormat length] == 0) {
            _willExpireFormat = [[NSBundle bundleForClass:[self class]] localizedStringForKey:kHITPADPassWillExpireFormat value:defaultWillExpireFormat table:nil];
        }
        
        if ([_tooltip length] == 0) {
            _tooltip = [[NSBundle bundleForClass:[self class]] localizedStringForKey:kHITPADPassTooltip value:defaultTooltip table:nil];
        }
        
        if ([_offlineTooltip length] == 0) {
            _offlineTooltip = [[NSBundle bundleForClass:[self class]] localizedStringForKey:kHITPADPassOfflineTooltip value:defaultOfflineTooltip table:nil];
        }
        
        
        
        NSString *defaultNotificationTitle = @"🔐 📆 ⚠️";
        NSString *defaultNotificationMessageFormat = @"Your password will expire on %@. Change it before!";
        NSString *defaultNotificationOfflineMessageFormat = @"Your password will expire on %@. Come back on your corporate network and change it before!";
        
        _notificationTitle = [settings objectForKey:kHITPADPassNotifTitle];
        _notificationMessageFormat = [settings objectForKey:kHITPADPassNotifMessageFormat];
        _notificationOfflineMessageFormat = [settings objectForKey:kHITPADPassNotifOfflineMessageFormat];
        
        if ([_notificationTitle length] == 0) {
            _notificationTitle = [[NSBundle bundleForClass:[self class]] localizedStringForKey:kHITPADPassNotifTitle value:defaultNotificationTitle table:nil];
        }
        
        if ([_notificationMessageFormat length] == 0) {
            _notificationMessageFormat = [[NSBundle bundleForClass:[self class]] localizedStringForKey:kHITPADPassNotifMessageFormat value:defaultNotificationMessageFormat table:nil];
        }
        
        if ([_notificationOfflineMessageFormat length] == 0) {
            _notificationOfflineMessageFormat = [[NSBundle bundleForClass:[self class]] localizedStringForKey:kHITPADPassNotifOfflineMessageFormat value:defaultNotificationOfflineMessageFormat table:nil];
        }


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
    
    NSDateComponents *components = [[NSCalendar currentCalendar] components:NSCalendarUnitDay fromDate:[NSDate date] toDate:self.passwordExpiryDate options:0];
    long daysBeforeExpiry = (long)[components day];
    self.menuItem.title = [NSString stringWithFormat:self.willExpireFormat, daysBeforeExpiry];
    
    if (self.lastADRequestSucceded) {
        self.menuItem.target = self;
        self.menuItem.toolTip = self.tooltip;
    } else {
        self.menuItem.target = nil;
        self.menuItem.toolTip = self.offlineTooltip;
    }
        
    if (daysBeforeExpiry <= self.alertXDaysBefore) {
        NSDate *dateOfLastNotification = [[NSUserDefaults standardUserDefaults] objectForKey:kHITPADPassLastNotifKey];
        
        BOOL notifNeeded = NO;
        
        if (dateOfLastNotification) {
            NSDateComponents *previousNotifComponents = [[NSCalendar currentCalendar] components:NSCalendarUnitDay fromDate:dateOfLastNotification toDate:self.passwordExpiryDate options:0];
            notifNeeded = [previousNotifComponents day] != daysBeforeExpiry;
        } else {
            notifNeeded = YES;
        }
        
        if (notifNeeded) {
            NSDateComponents* components = [[NSCalendar  currentCalendar] components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute fromDate:[NSDate date]];
            
            components.hour = 10;
            components.minute = 00;
            
            NSDate* deliveryDate = [[NSCalendar  currentCalendar] dateFromComponents:components];
            
            [self sendUserNotificationWithDeliveryDate:deliveryDate];
            [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:kHITPADPassLastNotifKey];
        }
    }
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

        
        self.passwordExpiryDate = [NSDate dateWithTimeInterval:expiryTimeInterval sinceDate:adRefenreceDate];
        self.lastADRequestSucceded = YES;
        
        [[NSUserDefaults standardUserDefaults] setInteger:[self.passwordExpiryDate timeIntervalSince1970] forKey:kHITPADPassExpiryTimeKey];
    } else {
        NSInteger expirySince1970 = [[NSUserDefaults standardUserDefaults] integerForKey:kHITPADPassExpiryTimeKey];
        self.passwordExpiryDate = [NSDate dateWithTimeIntervalSince1970:expirySince1970];
        self.lastADRequestSucceded = NO;
    }
}

- (void)sendUserNotificationWithDeliveryDate:(NSDate*)deliveryDate {
    NSUserNotification *notification = [NSUserNotification new];
    
    notification.deliveryDate = deliveryDate;
    notification.title = self.notificationTitle;
    NSString *infoTextFormat = self.lastADRequestSucceded ? self.notificationMessageFormat : self.notificationOfflineMessageFormat;
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
    [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
    
    NSString *stringDate = [dateFormatter stringFromDate:self.passwordExpiryDate];
    notification.informativeText = [NSString stringWithFormat:infoTextFormat, stringDate];
    
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
}

@end
