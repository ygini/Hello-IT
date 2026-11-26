//
//  HITPMunki.m
//  Munki
//
//  Built-in Munki values: manifest name, pending update count.
//  Replaces the example scripted items under example/munki_related.
//

#import "HITPMunki.h"

#import <IOKit/IOKitLib.h>
#import <sys/utsname.h>

#define kHITPMunkiKindKey @"kind"
#define kHITPManagedInstallsPlist @"/Library/Preferences/ManagedInstalls.plist"
#define kHITPManagedInstallsManifestsDir @"/Library/Managed Installs/manifests"
#define kHITPManagedSoftwareCenterApp @"/Applications/Managed Software Center.app"

typedef NS_ENUM(NSInteger, HITPMunkiKind) {
    HITPMunkiKindManifest = 0,
    HITPMunkiKindPending,
};

@interface HITPMunki ()
@property HITPMunkiKind kind;
@end

@implementation HITPMunki

#pragma mark - Lifecycle

- (instancetype)initWithSettings:(NSDictionary *)settings {
    self = [super initWithSettings:settings];
    if (self) {
        _kind = [self kindFromString:[settings objectForKey:kHITPMunkiKindKey]];
    }
    return self;
}

- (HITPMunkiKind)kindFromString:(NSString *)raw {
    NSString *kind = raw.lowercaseString;
    if ([kind isEqualToString:@"pending"]
        || [kind isEqualToString:@"pendingupdates"]
        || [kind isEqualToString:@"pending-update-count"]
        || [kind isEqualToString:@"updates"]) {
        return HITPMunkiKindPending;
    }
    return HITPMunkiKindManifest;
}

- (NSString *)fallbackSystemSymbolName {
    switch (self.kind) {
        case HITPMunkiKindManifest: return @"doc.text";
        case HITPMunkiKindPending: return @"arrow.down.app";
    }
    return @"shippingbox";
}

#pragma mark - Actions

- (void)mainAction:(id)sender {
    NSURL *appURL = [NSURL fileURLWithPath:kHITPManagedSoftwareCenterApp];
    if ([[NSFileManager defaultManager] fileExistsAtPath:appURL.path]) {
        [[NSWorkspace sharedWorkspace] openURL:appURL];
    }
}

- (void)periodicAction:(NSTimer *)timer {
    [self refreshDisplay];
}

- (NSMenuItem *)prepareNewMenuItem {
    NSMenuItem *item = [super prepareNewMenuItem];
    [self performSelector:@selector(refreshDisplay) withObject:nil afterDelay:0];
    return item;
}

#pragma mark - Refresh

- (void)refreshDisplay {
    if (!self.allowedToRun) {
        return;
    }

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSString *title = nil;
        NSString *tooltip = nil;
        HITPluginTestState state = HITPluginTestStateNone;

        switch (self.kind) {
            case HITPMunkiKindManifest:
                [self buildManifestTitle:&title tooltip:&tooltip state:&state];
                break;
            case HITPMunkiKindPending:
                [self buildPendingTitle:&title tooltip:&tooltip state:&state];
                break;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.allowedToRun) {
                return;
            }
            if (title) {
                [self setMenuTitle:title];
            }
            if (tooltip) {
                self.menuItem.toolTip = tooltip;
                self.menuItem.accessibilityHelp = tooltip;
            }
            self.testState = state;
        });
    });
}

#pragma mark - ManagedInstalls helpers

- (id)managedInstallsValueForKey:(NSString *)key {
    if (key.length == 0) {
        return nil;
    }
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                         CFSTR("ManagedInstalls"));
    if (value) {
        return CFBridgingRelease(value);
    }
    // Fallback for environments where CFPreferences misses the domain.
    NSDictionary *plist = [NSDictionary dictionaryWithContentsOfFile:kHITPManagedInstallsPlist];
    return plist[key];
}

- (NSString *)platformSerialNumber {
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                       IOServiceMatching("IOPlatformExpertDevice"));
    if (!service) {
        return nil;
    }
    CFTypeRef serial = IORegistryEntryCreateCFProperty(service,
                                                       CFSTR("IOPlatformSerialNumber"),
                                                       kCFAllocatorDefault,
                                                       0);
    IOObjectRelease(service);
    if (!serial) {
        return nil;
    }
    return CFBridgingRelease(serial);
}

- (NSString *)shortHostname {
    struct utsname uts;
    if (uname(&uts) != 0) {
        return nil;
    }
    return [NSString stringWithUTF8String:uts.nodename];
}

- (BOOL)manifestFileExistsForName:(NSString *)name {
    if (name.length == 0) {
        return NO;
    }
    NSString *path = [kHITPManagedInstallsManifestsDir stringByAppendingPathComponent:name];
    return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

#pragma mark - Manifest

- (void)buildManifestTitle:(NSString **)title tooltip:(NSString **)tooltip state:(HITPluginTestState *)state {
    id raw = [self managedInstallsValueForKey:@"ClientIdentifier"];
    NSString *clientIdentifier = [raw isKindOfClass:[NSString class]] ? raw : nil;

    if (clientIdentifier.length > 0) {
        *title = [NSString stringWithFormat:@"Manifest: %@", clientIdentifier];
        *tooltip = @"Click to open Managed Software Center.";
        *state = HITPluginTestStateNone;
        return;
    }

    NSString *serial = [self platformSerialNumber];
    NSString *hostname = [self shortHostname];
    if ([self manifestFileExistsForName:serial] || [self manifestFileExistsForName:hostname]) {
        *title = @"Using Serial/Hostname Manifest.";
        *tooltip = @"Your device is using its serial or hostname as a manifest. This is intended behavior.";
        *state = HITPluginTestStateNone;
        return;
    }

    *title = @"No ClientIdentifier found!";
    *tooltip = @"Your manifest is not found. Managed Software Center requires this.";
    *state = HITPluginTestStateError;
}

#pragma mark - Pending updates

- (void)buildPendingTitle:(NSString **)title tooltip:(NSString **)tooltip state:(HITPluginTestState *)state {
    id rawCount = [self managedInstallsValueForKey:@"PendingUpdateCount"];
    NSInteger pending = 0;
    if ([rawCount respondsToSelector:@selector(integerValue)]) {
        pending = [rawCount integerValue];
    }

    if (pending <= 0) {
        *title = @"No Pending MSC Updates";
        *tooltip = @"No available updates.";
        *state = HITPluginTestStateNone;
        return;
    }

    id rawRestart = [self managedInstallsValueForKey:@"RestartRequired"];
    BOOL restartRequired = NO;
    if ([rawRestart isKindOfClass:[NSNumber class]]) {
        restartRequired = [(NSNumber *)rawRestart boolValue];
    } else if ([rawRestart isKindOfClass:[NSString class]]) {
        NSString *value = [(NSString *)rawRestart stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]].lowercaseString;
        // Match `defaults read`-style booleans; ignore empty / falsey strings.
        restartRequired = [value isEqualToString:@"1"]
            || [value isEqualToString:@"true"]
            || [value isEqualToString:@"yes"]
            || [value isEqualToString:@"y"];
    } else if ([rawRestart respondsToSelector:@selector(boolValue)]) {
        restartRequired = [rawRestart boolValue];
    }

    if (restartRequired) {
        *title = [NSString stringWithFormat:@"Pending MSC Updates: %ld. Restart Required!", (long)pending];
        *tooltip = @"Your updates require a restart. Click to open Managed Software Center.";
        *state = HITPluginTestStateError;
    } else {
        *title = [NSString stringWithFormat:@"Pending MSC Updates: %ld", (long)pending];
        *tooltip = @"Updates available. Click to open Managed Software Center.";
        *state = HITPluginTestStateWarning;
    }
}

@end
