//
//  HITPSendEmail.m
//  SendEmail
//
//  Opens a prefilled email (default mailto: handler or Gmail compose) with
//  optional subject/body. deviceURL and templates support $SERIAL, $UUID,
//  $HOSTNAME, and $DEVICE_URL (resolved deviceURL for subject/body).
//

#import "HITPSendEmail.h"

#import <AppKit/AppKit.h>
#import <IOKit/IOKitLib.h>
#import <os/log.h>

#define kHITPSendEmailMailtoKey @"mailto"
#define kHITPSendEmailDeviceURLKey @"deviceURL"
#define kHITPSendEmailMailerKey @"mailer"
#define kHITPSendEmailSubjectKey @"subject"
#define kHITPSendEmailBodyKey @"body"

typedef NS_ENUM(NSInteger, HITPSendEmailMailer) {
    HITPSendEmailMailerDefault = 0,
    HITPSendEmailMailerGmail,
};

@interface HITPSendEmail ()
@property (copy) NSString *mailto;
@property (copy) NSString *deviceURLTemplate;
@property (copy) NSString *subjectTemplate;
@property (copy) NSString *bodyTemplate;
@property HITPSendEmailMailer mailer;
@end

@implementation HITPSendEmail

- (instancetype)initWithSettings:(NSDictionary *)settings {
    self = [super initWithSettings:settings];
    if (self) {
        _mailto = [[settings objectForKey:kHITPSendEmailMailtoKey] copy] ?: @"";
        _deviceURLTemplate = [[settings objectForKey:kHITPSendEmailDeviceURLKey] copy] ?: @"";
        _subjectTemplate = [[settings objectForKey:kHITPSendEmailSubjectKey] copy] ?: @"";
        _bodyTemplate = [[settings objectForKey:kHITPSendEmailBodyKey] copy] ?: @"";
        _mailer = [self mailerFromString:[settings objectForKey:kHITPSendEmailMailerKey]];
    }
    return self;
}

- (HITPSendEmailMailer)mailerFromString:(NSString *)raw {
    NSString *value = raw.lowercaseString;
    if ([value isEqualToString:@"gmail"]
        || [value isEqualToString:@"google"]
        || [value isEqualToString:@"googlemail"]) {
        return HITPSendEmailMailerGmail;
    }
    return HITPSendEmailMailerDefault;
}

- (NSString *)fallbackSystemSymbolName {
    return @"envelope";
}

#pragma mark - Device identity

- (NSString *)platformProperty:(CFStringRef)key {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                       IOServiceMatching("IOPlatformExpertDevice"));
    if (!service) {
        return @"";
    }
    CFTypeRef value = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0);
    IOObjectRelease(service);
    if (!value) {
        return @"";
    }
    if (CFGetTypeID(value) == CFStringGetTypeID()) {
        return CFBridgingRelease(value);
    }
    CFRelease(value);
    return @"";
}

- (NSString *)platformSerialNumber {
    return [self platformProperty:CFSTR("IOPlatformSerialNumber")];
}

- (NSString *)platformUUID {
    return [self platformProperty:CFSTR("IOPlatformUUID")];
}

- (NSString *)computerHostname {
    NSString *name = [[NSHost currentHost] localizedName];
    if (name.length > 0) {
        return name;
    }
    name = [[NSHost currentHost] name];
    return name.length ? name : @"";
}

#pragma mark - Templates

- (NSString *)stringByApplyingPlaceholders:(NSString *)template
                                    serial:(NSString *)serial
                                      uuid:(NSString *)uuid
                                  hostname:(NSString *)hostname
                                 deviceURL:(NSString *)deviceURL {
    if (template.length == 0) {
        return @"";
    }
    NSMutableString *result = [template mutableCopy];
    NSDictionary *map = @{
        @"$SERIAL": serial ?: @"",
        @"$UUID": uuid ?: @"",
        @"$HOSTNAME": hostname ?: @"",
        @"$DEVICE_URL": deviceURL ?: @"",
    };
    [map enumerateKeysAndObjectsUsingBlock:^(NSString *token, NSString *value, BOOL *stop) {
        [result replaceOccurrencesOfString:token
                                withString:value
                                   options:0
                                     range:NSMakeRange(0, result.length)];
    }];
    return [result copy];
}

- (NSString *)percentEncodedQueryValue:(NSString *)value {
    if (value.length == 0) {
        return @"";
    }
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:
                               @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
    return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: @"";
}

#pragma mark - Action

- (void)mainAction:(id)sender {
    NSString *serial = [self platformSerialNumber];
    NSString *uuid = [self platformUUID];
    NSString *hostname = [self computerHostname];

    NSString *deviceURL = [self stringByApplyingPlaceholders:self.deviceURLTemplate
                                                     serial:serial
                                                       uuid:uuid
                                                   hostname:hostname
                                                  deviceURL:@""];

    NSString *subject = [self stringByApplyingPlaceholders:self.subjectTemplate
                                                    serial:serial
                                                      uuid:uuid
                                                  hostname:hostname
                                                 deviceURL:deviceURL];

    // Leading blank lines + protected marker sit above the device URL so helpdesk
    // tools can parse it and users are less likely to edit it.
    static NSString * const kHITPSendEmailDeviceURLBlock =
        @"\n\n\n\n\n\n\nPlease do not edit the line below\n---------------------------------\n$DEVICE_URL";

    NSString *bodyTemplate = self.bodyTemplate;
    if (deviceURL.length > 0) {
        if (bodyTemplate.length == 0) {
            bodyTemplate = kHITPSendEmailDeviceURLBlock;
        } else if ([bodyTemplate rangeOfString:@"$DEVICE_URL"].location == NSNotFound) {
            bodyTemplate = [bodyTemplate stringByAppendingString:kHITPSendEmailDeviceURLBlock];
        }
    }
    NSString *body = [self stringByApplyingPlaceholders:bodyTemplate
                                                 serial:serial
                                                   uuid:uuid
                                               hostname:hostname
                                              deviceURL:deviceURL];

    if (self.mailto.length == 0) {
        os_log_error(OS_LOG_DEFAULT, "SendEmail: mailto is empty; nothing to open.");
        return;
    }

    NSURL *url = nil;
    if (self.mailer == HITPSendEmailMailerGmail) {
        // Do not put serial/UUID/hostname body into a Gmail GET URL (browser history / proxies).
        // Copy the body to the pasteboard and open compose with to + subject only.
        if (body.length > 0) {
            NSPasteboard *pb = [NSPasteboard generalPasteboard];
            // Prefer writing the string type without wiping other pasteboard representations.
            if (![pb setString:body forType:NSPasteboardTypeString]) {
                [pb declareTypes:@[NSPasteboardTypeString] owner:nil];
                [pb setString:body forType:NSPasteboardTypeString];
            }
            os_log_info(OS_LOG_DEFAULT, "SendEmail: Gmail body copied to pasteboard (%lu chars).",
                        (unsigned long)body.length);
        }
        NSMutableArray *parts = [NSMutableArray array];
        [parts addObject:[NSString stringWithFormat:@"to=%@", [self percentEncodedQueryValue:self.mailto]]];
        if (subject.length > 0) {
            [parts addObject:[NSString stringWithFormat:@"su=%@", [self percentEncodedQueryValue:subject]]];
        }
        NSString *gmail = [NSString stringWithFormat:
                           @"https://mail.google.com/mail/?view=cm&fs=1&%@",
                           [parts componentsJoinedByString:@"&"]];
        url = [NSURL URLWithString:gmail];
    } else {
        NSMutableArray *parts = [NSMutableArray array];
        if (subject.length > 0) {
            [parts addObject:[NSString stringWithFormat:@"subject=%@", [self percentEncodedQueryValue:subject]]];
        }
        if (body.length > 0) {
            [parts addObject:[NSString stringWithFormat:@"body=%@", [self percentEncodedQueryValue:body]]];
        }
        // Encode the address so spaces / unicode don't yield a nil NSURL.
        NSString *encodedAddress = [self percentEncodedQueryValue:self.mailto];
        NSString *mailtoURL = [NSString stringWithFormat:@"mailto:%@", encodedAddress];
        if (parts.count > 0) {
            mailtoURL = [mailtoURL stringByAppendingFormat:@"?%@", [parts componentsJoinedByString:@"&"]];
        }
        url = [NSURL URLWithString:mailtoURL];
    }

    if (!url) {
        os_log_error(OS_LOG_DEFAULT, "SendEmail: failed to build URL for mailto=%s",
                     [self.mailto cStringUsingEncoding:NSUTF8StringEncoding]);
        return;
    }

    os_log_info(OS_LOG_DEFAULT, "SendEmail: opening %s",
                [[url absoluteString] cStringUsingEncoding:NSUTF8StringEncoding]);
    [[NSWorkspace sharedWorkspace] openURL:url];
}

@end
