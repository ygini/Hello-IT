//
//  HITAdvancedPlugin.h
//  HITDevKit
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITSimplePlugin.h"

@interface HITAdvancedPlugin : HITSimplePlugin

#define kHITAdvancedPluginSkipForGlobalStateKey @"skipForGlobalState"

#define kHITNotificationMessageForOKKey @"notificationWhenStateTurnOK"
#define kHITNotificationMessageForNoneKey @"notificationWhenStateTurnNone"
#define kHITNotificationMessageForWarningKey @"notificationWhenStateTurnWarning"
#define kHITNotificationMessageForErrorKey @"notificationWhenStateTurnError"
#define kHITNotificationMessageForUnavailableKey @"notificationWhenStateTurnUnavailable"

@property (nonatomic) HITPluginTestState testState;
@property (nonatomic) BOOL skipForGlobalState;

@end
