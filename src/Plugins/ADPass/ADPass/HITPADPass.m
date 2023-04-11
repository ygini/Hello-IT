//
//  HITPADPass.m
//  ADPass
//
//  Created by Yoann Gini on 24/09/2017.
//  Copyright © 2017 Yoann Gini. All rights reserved.
//

#import "HITPADPass.h"
#import <OpenDirectory/OpenDirectory.h>
#import <os/log.h>

#define kHITPADPassExpiryTimeField @"msDS-UserPasswordExpiryTimeComputed"
#define kHITPADPassExpiryTimeKey @"public.ad.pass.expirySince1970"
#define kHITPADPassLastNotifKey @"public.ad.pass.lastNotification"

#define kHITPADPassWillExpireFormat @"willExpireFormat"
#define kHITPADPassNeverExpireInfo @"neverExpireInfo"
#define kHITPADPassTooltip @"tooltip"
#define kHITPADPassOfflineTooltip @"offlineTooltip"

#define kHITPADPassNotifTitle @"notificationTitle"
#define kHITPADPassNotifMessageFormat @"notificationMessageFormat"
#define kHITPADPassNotifOfflineMessageFormat @"notificationOfflineMessageFormat"
#define kHITPADPassNotifChangePasswordTitle @"notificationChangePasswordTitle"
#define kHITPADPassNotifLaterTitle @"notificationLaterTitle"

#define kHITPADPassAlertXDaysBefore @"alertXDaysBefore"

@interface HITPADPass ()

@property NSDate *passwordExpiryDate;
@property BOOL lastADRequestSucceded;

@property NSString *localeTablePath;

@property NSString *willExpireFormat;
@property NSString *neverExpireInfo;
@property NSString *tooltip;
@property NSString *offlineTooltip;

@property NSString *notificationTitle;
@property NSString *notificationMessageFormat;
@property NSString *notificationOfflineMessageFormat;
@property NSString *notificationChangePasswordTitle;
@property NSString *notificationLaterTitle;

@property NSInteger alertXDaysBefore;

@property id<HITPluginsManagerProtocol> pluginsManager;

@end

@implementation HITPADPass

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        if ([settings.allKeys containsObject:kHITPADPassAlertXDaysBefore]) {
            _alertXDaysBefore = [[settings objectForKey:kHITPADPassAlertXDaysBefore] integerValue];
        } else {
            _alertXDaysBefore = 15;
        }
        
        NSString *defaultWillExpireFormat = @"🔐 📆 %ld";
        NSString *defaultNeverExpireInfo = @"🔐 ∞";
        NSString *defaultTooltip = @"Delay before your password expire, change it before!";
        NSString *defaultOfflineTooltip = @"Your IT infrastructure isn't available. Current info is based on the last recorded value.";
        
        _willExpireFormat = [settings objectForKey:kHITPADPassWillExpireFormat];
        _neverExpireInfo = [settings objectForKey:kHITPADPassNeverExpireInfo];
        _tooltip = [settings objectForKey:kHITPADPassTooltip];
        _offlineTooltip = [settings objectForKey:kHITPADPassOfflineTooltip];
        
        if ([_willExpireFormat length] == 0) {
            _willExpireFormat = [[NSBundle bundleForClass:[self class]] localizedStringForKey:kHITPADPassWillExpireFormat value:defaultWillExpireFormat table:nil];
        }
        
        if ([_neverExpireInfo length] == 0) {
            _neverExpireInfo = [[NSBundle bundleForClass:[self class]] localizedStringForKey:kHITPADPassNeverExpireInfo value:defaultNeverExpireInfo table:nil];
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
        NSString *defaultNotificationChangePasswordTitle = @"🔑";
        NSString *defaultNotificationLaterTitle = @"⏰";
        
        _notificationTitle = [settings objectForKey:kHITPADPassNotifTitle];
        _notificationMessageFormat = [settings objectForKey:kHITPADPassNotifMessageFormat];
        _notificationOfflineMessageFormat = [settings objectForKey:kHITPADPassNotifOfflineMessageFormat];
        _notificationChangePasswordTitle = [settings objectForKey:kHITPADPassNotifChangePasswordTitle];
        _notificationLaterTitle = [settings objectForKey:kHITPADPassNotifLaterTitle];
        
        if ([_notificationTitle length] == 0) {
            _notificationTitle = [[NSBundle bundleForClass:[self class]] localizedStringForKey:kHITPADPassNotifTitle value:defaultNotificationTitle table:nil];
        }
        
        if ([_notificationMessageFormat length] == 0) {
            _notificationMessageFormat = [[NSBundle bundleForClass:[self class]] localizedStringForKey:kHITPADPassNotifMessageFormat value:defaultNotificationMessageFormat table:nil];
        }
        
        if ([_notificationOfflineMessageFormat length] == 0) {
            _notificationOfflineMessageFormat = [[NSBundle bundleForClass:[self class]] localizedStringForKey:kHITPADPassNotifOfflineMessageFormat value:defaultNotificationOfflineMessageFormat table:nil];
        }
        
        if ([_notificationChangePasswordTitle length] == 0) {
            _notificationChangePasswordTitle = [[NSBundle bundleForClass:[self class]] localizedStringForKey:kHITPADPassNotifChangePasswordTitle value:defaultNotificationChangePasswordTitle table:nil];
        }
        
        if ([_notificationLaterTitle length] == 0) {
            _notificationLaterTitle = [[NSBundle bundleForClass:[self class]] localizedStringForKey:kHITPADPassNotifLaterTitle value:defaultNotificationLaterTitle table:nil];
        }
        
    }
    return self;
}

- (void)mainAction:(id)sender {
    [[NSWorkspace sharedWorkspace] openFile:@"/System/Library/PreferencePanes/Accounts.prefPane"];
}

- (void)periodicAction:(NSTimer *)timer {
    [self backgroundFetchPasswordExpiryDate];
}

- (void)updateTitle {
    if (self.passwordExpiryDate) {
        self.menuItem.hidden = NO;
        NSDateComponents *components = [[NSCalendar currentCalendar] components:NSCalendarUnitDay fromDate:[NSDate date] toDate:self.passwordExpiryDate options:0];
        long daysBeforeExpiry = (long)[components day];
        if (daysBeforeExpiry < 0) daysBeforeExpiry = 0;
        
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
            
            NSDateComponents* components = [[NSCalendar  currentCalendar] components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute fromDate:[NSDate date]];
            
            if (components.hour >= 10 && notifNeeded) {
                [self sendUserNotification];
            }
        }
    } else {
        os_log_info(OS_LOG_DEFAULT, "No AD Password expiry date found, hidding menu item.");
        self.menuItem.hidden = YES;
    }
}

- (void)backgroundFetchPasswordExpiryDate {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0) , ^{
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
            os_log_info(OS_LOG_DEFAULT, "AD Password expiry date requested with success.");
            
            if ([expiryTime integerValue] == 0x7FFFFFFFFFFFFFFF) {
                os_log_info(OS_LOG_DEFAULT, "AD Password expiry date is mean no expiry.");
                self.passwordExpiryDate = nil;
                self.lastADRequestSucceded = YES;
                [[NSUserDefaults standardUserDefaults] setInteger:-1 forKey:kHITPADPassExpiryTimeKey];
            } else {
                os_log_info(OS_LOG_DEFAULT, "AD Password expiry date is a valid date.");
                
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
            }
        } else {
            os_log_info(OS_LOG_DEFAULT, "Unable to reach AD, working with old expiry date for AD Password.");
            NSInteger expirySince1970 = [[NSUserDefaults standardUserDefaults] integerForKey:kHITPADPassExpiryTimeKey];
            if (expirySince1970 == -1) {
                self.passwordExpiryDate = nil;
            } else {
                self.passwordExpiryDate = expirySince1970 > 0 ? [NSDate dateWithTimeIntervalSince1970:expirySince1970] : nil;
            }
            self.lastADRequestSucceded = NO;
        }
        dispatch_async(dispatch_get_main_queue() , ^{
            [self updateTitle];
        });
    });
}

- (void)sendUserNotification {
    os_log_info(OS_LOG_DEFAULT, "Notification to change AD password is requested.");
    NSUserNotification *notification = [NSUserNotification new];
    
    notification.title = self.notificationTitle;
    NSString *infoTextFormat = self.lastADRequestSucceded ? self.notificationMessageFormat : self.notificationOfflineMessageFormat;
    
    notification.hasActionButton = YES;
    notification.actionButtonTitle = self.notificationChangePasswordTitle;
    notification.otherButtonTitle = self.notificationLaterTitle;
    
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
    [dateFormatter setTimeStyle:NSDateFormatterShortStyle];
    
    NSString *stringDate = [dateFormatter stringFromDate:self.passwordExpiryDate];
    notification.informativeText = [NSString stringWithFormat:infoTextFormat, stringDate];
    
    [[NSUserNotificationCenter defaultUserNotificationCenter] deliverNotification:notification];
    [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:kHITPADPassLastNotifKey];
    
    [self.pluginsManager sendNotification:notification from:self];
}

- (void)actionFromNotification:(NSUserNotification*)notification {
    [self mainAction:notification];
}

@end
