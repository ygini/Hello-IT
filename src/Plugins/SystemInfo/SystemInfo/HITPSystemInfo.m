//
//  HITPSystemInfo.m
//  SystemInfo
//
//  Built-in system values: hostname, IP, Wi-Fi, Ethernet speed, storage,
//  uptime, memory pressure. Scripts remain for custom / org-specific items.
//

#import "HITPSystemInfo.h"

#import <ifaddrs.h>
#import <net/if.h>
#import <net/if_media.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <sys/ioctl.h>
#import <sys/socket.h>
#import <sys/sysctl.h>
#import <sys/time.h>
#import <unistd.h>
#import <string.h>
#import <CoreWLAN/CoreWLAN.h>
#import <SystemConfiguration/SystemConfiguration.h>

#define kHITPSystemInfoKindKey @"kind"
#define kHITPSystemInfoFormatKey @"format"
#define kHITPSystemInfoInterfaceKey @"interface"
#define kHITPSystemInfoModeKey @"mode"
#define kHITPSystemInfoArgsKey @"args"
#define kHITPSystemInfoWarnDaysKey @"warnDays"
#define kHITPSystemInfoErrorDaysKey @"errorDays"
#define kHITPSystemInfoWarnPercentKey @"warnPercent"
#define kHITPSystemInfoErrorPercentKey @"errorPercent"
#define kHITPSystemInfoWarnBelowGBKey @"warnBelowGB"
#define kHITPSystemInfoErrorBelowGBKey @"errorBelowGB"
#define kHITPSystemInfoWarnBelowSNRKey @"warnBelowSNR"
#define kHITPSystemInfoErrorBelowSNRKey @"errorBelowSNR"

// kern.memorystatus_vm_pressure_level (Dispatch / knote levels).
// Kernel WARN (2) fires early (~50% pressure) so apps can drop caches; Activity
// Monitor’s graph often stays green until much higher — menu state follows the
// AM-style percentage below, and always errors on kernel CRITICAL (4).
#define kHITMemoryPressureNormal   1
#define kHITMemoryPressureWarning  2
#define kHITMemoryPressureCritical 4

// Activity Monitor–style pressure % = 100 − kern.memorystatus_level
static const NSInteger kHITMemoryWarnAtPercent = 70;
static const NSInteger kHITMemoryErrorAtPercent = 85;

// Uptime thresholds (whole days since boot)
static const NSInteger kHITUptimeWarnDays = 7;
static const NSInteger kHITUptimeErrorDays = 14;

// Storage free-space thresholds (decimal GB)
static const NSInteger kHITStorageWarnBelowGB = 50;
static const NSInteger kHITStorageErrorBelowGB = 10;

// Wi‑Fi SNR thresholds (dB)
static const NSInteger kHITWiFiWarnBelowSNR = 25;
static const NSInteger kHITWiFiErrorBelowSNR = 15;

typedef NS_ENUM(NSInteger, HITPSystemInfoKind) {
    HITPSystemInfoKindHostname = 0,
    HITPSystemInfoKindIP,
    HITPSystemInfoKindWiFi,
    HITPSystemInfoKindEthernet,
    HITPSystemInfoKindStorage,
    HITPSystemInfoKindUptime,
    HITPSystemInfoKindMemory,
};

@interface HITPSystemInfo ()
@property HITPSystemInfoKind kind;
@property NSString *format;
@property NSString *interface;
@property NSInteger mode;
@property NSInteger uptimeWarnDays;
@property NSInteger uptimeErrorDays;
@property NSInteger memoryWarnPercent;
@property NSInteger memoryErrorPercent;
@property NSInteger storageWarnBelowGB;
@property NSInteger storageErrorBelowGB;
@property NSInteger wifiWarnBelowSNR;
@property NSInteger wifiErrorBelowSNR;
@property (copy) NSString *lastCopyValue;
@end

@implementation HITPSystemInfo

#pragma mark - Lifecycle

- (instancetype)initWithSettings:(NSDictionary *)settings {
    self = [super initWithSettings:settings];
    if (self) {
        _kind = [self kindFromString:[settings objectForKey:kHITPSystemInfoKindKey]];
        _interface = [settings objectForKey:kHITPSystemInfoInterfaceKey] ?: @"";
        _mode = [[settings objectForKey:kHITPSystemInfoModeKey] integerValue];

        NSString *format = [settings objectForKey:kHITPSystemInfoFormatKey];
        if ([format length] == 0) {
            NSDictionary *args = [settings objectForKey:kHITPSystemInfoArgsKey];
            if ([args isKindOfClass:[NSDictionary class]]) {
                format = args[kHITPSystemInfoFormatKey];
            }
        }
        _format = [format length] > 0 ? format : @"%C";
        _lastCopyValue = @"";

        NSInteger warnDays = [[settings objectForKey:kHITPSystemInfoWarnDaysKey] integerValue];
        NSInteger errorDays = [[settings objectForKey:kHITPSystemInfoErrorDaysKey] integerValue];
        _uptimeWarnDays = warnDays > 0 ? warnDays : kHITUptimeWarnDays;
        _uptimeErrorDays = errorDays > 0 ? errorDays : kHITUptimeErrorDays;

        NSInteger warnPercent = [[settings objectForKey:kHITPSystemInfoWarnPercentKey] integerValue];
        NSInteger errorPercent = [[settings objectForKey:kHITPSystemInfoErrorPercentKey] integerValue];
        _memoryWarnPercent = warnPercent > 0 ? warnPercent : kHITMemoryWarnAtPercent;
        _memoryErrorPercent = errorPercent > 0 ? errorPercent : kHITMemoryErrorAtPercent;

        NSInteger warnGB = [[settings objectForKey:kHITPSystemInfoWarnBelowGBKey] integerValue];
        NSInteger errorGB = [[settings objectForKey:kHITPSystemInfoErrorBelowGBKey] integerValue];
        _storageWarnBelowGB = warnGB > 0 ? warnGB : kHITStorageWarnBelowGB;
        _storageErrorBelowGB = errorGB > 0 ? errorGB : kHITStorageErrorBelowGB;

        NSInteger warnSNR = [[settings objectForKey:kHITPSystemInfoWarnBelowSNRKey] integerValue];
        NSInteger errorSNR = [[settings objectForKey:kHITPSystemInfoErrorBelowSNRKey] integerValue];
        _wifiWarnBelowSNR = warnSNR > 0 ? warnSNR : kHITWiFiWarnBelowSNR;
        _wifiErrorBelowSNR = errorSNR > 0 ? errorSNR : kHITWiFiErrorBelowSNR;
    }
    return self;
}

- (HITPSystemInfoKind)kindFromString:(NSString *)raw {
    NSString *safe = raw;
    if (safe.length == 0) {
        return HITPSystemInfoKindHostname;
    }
    NSString *kind = [safe lowercaseString];
    if ([kind isEqualToString:@"ip"] || [kind isEqualToString:@"address"]) {
        return HITPSystemInfoKindIP;
    }
    if ([kind isEqualToString:@"wifi"] || [kind isEqualToString:@"wi-fi"] || [kind isEqualToString:@"wlan"]) {
        return HITPSystemInfoKindWiFi;
    }
    if ([kind isEqualToString:@"ethernet"] || [kind isEqualToString:@"ether"] || [kind isEqualToString:@"lan"]) {
        return HITPSystemInfoKindEthernet;
    }
    if ([kind isEqualToString:@"storage"] || [kind isEqualToString:@"disk"] || [kind isEqualToString:@"space"]) {
        return HITPSystemInfoKindStorage;
    }
    if ([kind isEqualToString:@"uptime"] || [kind isEqualToString:@"boot"] || [kind isEqualToString:@"reboot"]) {
        return HITPSystemInfoKindUptime;
    }
    if ([kind isEqualToString:@"memory"] || [kind isEqualToString:@"memorypressure"] || [kind isEqualToString:@"memory_pressure"] || [kind isEqualToString:@"ram"]) {
        return HITPSystemInfoKindMemory;
    }
    return HITPSystemInfoKindHostname;
}

- (BOOL)isNetworkRelated {
    return self.kind == HITPSystemInfoKindIP
        || self.kind == HITPSystemInfoKindWiFi
        || self.kind == HITPSystemInfoKindEthernet;
}

- (NSString *)fallbackSystemSymbolName {
    switch (self.kind) {
        case HITPSystemInfoKindHostname: return @"desktopcomputer";
        case HITPSystemInfoKindIP: return @"network";
        case HITPSystemInfoKindWiFi: return @"wifi";
        case HITPSystemInfoKindEthernet: return @"cable.connector";
        case HITPSystemInfoKindStorage: return @"internaldrive";
        case HITPSystemInfoKindUptime: return @"clock";
        case HITPSystemInfoKindMemory: return @"memorychip";
    }
    return @"info.circle";
}

#pragma mark - Actions

- (void)mainAction:(id)sender {
    [self refreshDisplay];
    if (self.lastCopyValue.length > 0) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb setString:self.lastCopyValue forType:NSPasteboardTypeString];
    }
}

- (void)periodicAction:(NSTimer *)timer {
    [self refreshDisplay];
}

- (void)generalNetworkStateUpdate:(BOOL)state {
    if ([self isNetworkRelated]) {
        [self refreshDisplay];
    }
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
        NSString *copyValue = nil;
        HITPluginTestState state = HITPluginTestStateNone;
        BOOL hidden = NO;

        switch (self.kind) {
            case HITPSystemInfoKindHostname:
                [self buildHostnameTitle:&title tooltip:&tooltip copyValue:&copyValue];
                break;
            case HITPSystemInfoKindIP:
                [self buildIPTitle:&title tooltip:&tooltip copyValue:&copyValue state:&state hidden:&hidden];
                break;
            case HITPSystemInfoKindWiFi:
                [self buildWiFiTitle:&title tooltip:&tooltip copyValue:&copyValue state:&state hidden:&hidden];
                break;
            case HITPSystemInfoKindEthernet:
                [self buildEthernetTitle:&title tooltip:&tooltip copyValue:&copyValue state:&state hidden:&hidden];
                break;
            case HITPSystemInfoKindStorage:
                [self buildStorageTitle:&title tooltip:&tooltip copyValue:&copyValue state:&state];
                break;
            case HITPSystemInfoKindUptime:
                [self buildUptimeTitle:&title tooltip:&tooltip copyValue:&copyValue state:&state];
                break;
            case HITPSystemInfoKindMemory:
                [self buildMemoryTitle:&title tooltip:&tooltip copyValue:&copyValue state:&state];
                break;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.allowedToRun) {
                return;
            }
            self.lastCopyValue = copyValue ?: @"";
            self.menuItem.hidden = hidden;
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

#pragma mark - Hostname

- (void)buildHostnameTitle:(NSString **)title tooltip:(NSString **)tooltip copyValue:(NSString **)copyValue {
    NSString *computerName = [self scutilValue:@"ComputerName"] ?: @"";
    NSString *hostName = [self scutilValue:@"HostName"] ?: @"";
    NSString *localHostName = [self scutilValue:@"LocalHostName"] ?: @"";

    NSString *formatted = self.format;
    formatted = [formatted stringByReplacingOccurrencesOfString:@"%C" withString:computerName];
    formatted = [formatted stringByReplacingOccurrencesOfString:@"%H" withString:hostName];
    formatted = [formatted stringByReplacingOccurrencesOfString:@"%L" withString:localHostName];

    *copyValue = formatted;
    *title = [NSString stringWithFormat:@"Hostname: %@", formatted];
    *tooltip = [NSString stringWithFormat:@"Computer Name: %@\nHost Name: %@\nLocal Host Name: %@\nClick to copy",
                computerName, hostName.length ? hostName : @"—", localHostName.length ? localHostName : @"—"];
}

- (NSString *)scutilValue:(NSString *)key {
    // Mirror `scutil --get` using SystemConfiguration.
    if ([key isEqualToString:@"ComputerName"]) {
        CFStringRef name = SCDynamicStoreCopyComputerName(NULL, NULL);
        return name ? CFBridgingRelease(name) : nil;
    }
    if ([key isEqualToString:@"LocalHostName"]) {
        CFStringRef name = SCDynamicStoreCopyLocalHostName(NULL);
        return name ? CFBridgingRelease(name) : nil;
    }
    if ([key isEqualToString:@"HostName"]) {
        // preferences.plist → System → System → HostName (same as `scutil --get HostName`)
        SCPreferencesRef prefs = SCPreferencesCreate(NULL, CFSTR("Hello-IT"), NULL);
        if (prefs) {
            NSDictionary *system = (__bridge NSDictionary *)SCPreferencesGetValue(prefs, kSCPrefSystem);
            NSDictionary *nested = [system isKindOfClass:[NSDictionary class]] ? system[@"System"] : nil;
            NSString *hostName = [nested isKindOfClass:[NSDictionary class]] ? nested[@"HostName"] : nil;
            CFRelease(prefs);
            if ([hostName isKindOfClass:[NSString class]] && hostName.length > 0) {
                return hostName;
            }
        }

        char buf[256] = {0};
        if (gethostname(buf, sizeof(buf) - 1) == 0) {
            return [NSString stringWithUTF8String:buf];
        }
        return nil;
    }
    return nil;
}

#pragma mark - IP

- (void)buildIPTitle:(NSString **)title tooltip:(NSString **)tooltip copyValue:(NSString **)copyValue state:(HITPluginTestState *)state hidden:(BOOL *)hidden {
    NSString *bsd = self.interface.length > 0 ? self.interface : [self primaryBSDInterface];
    NSString *ip = [self ipv4AddressForBSDName:bsd];

    if (ip.length == 0) {
        *title = @"No IP Address";
        *copyValue = @"";
        if (self.mode == 0) {
            *hidden = YES;
            *state = HITPluginTestStateNone;
        } else if (self.mode == 1) {
            *hidden = NO;
            *state = HITPluginTestStateUnavailable;
            *tooltip = @"No network connection available";
        } else {
            *hidden = NO;
            *state = HITPluginTestStateError;
            *tooltip = @"Please check your Ethernet or Wi‑Fi connection";
        }
        return;
    }

    *hidden = NO;
    *title = [NSString stringWithFormat:@"Local IP: %@", ip];
    *copyValue = ip;
    *state = HITPluginTestStateOK;
    *tooltip = [NSString stringWithFormat:@"Interface: %@\nHaving an IP address doesn't mean you have Internet access\nClick to copy", bsd ?: @"—"];
}

- (NSString *)primaryBSDInterface {
    // Same idea as the script: interface used to reach 8.8.8.8
    SCDynamicStoreRef store = SCDynamicStoreCreate(NULL, CFSTR("Hello-IT"), NULL, NULL);
    if (!store) {
        return nil;
    }

    NSDictionary *globalIPv4 = CFBridgingRelease(SCDynamicStoreCopyValue(store, CFSTR("State:/Network/Global/IPv4")));
    CFRelease(store);
    NSString *primary = globalIPv4[@"PrimaryInterface"];
    return [primary isKindOfClass:[NSString class]] ? primary : nil;
}

- (NSString *)ipv4AddressForBSDName:(NSString *)bsdName {
    if (bsdName.length == 0) {
        return nil;
    }

    struct ifaddrs *ifap = NULL;
    if (getifaddrs(&ifap) != 0) {
        return nil;
    }

    NSString *result = nil;
    for (struct ifaddrs *ifa = ifap; ifa != NULL; ifa = ifa->ifa_next) {
        if (!ifa->ifa_addr || ifa->ifa_addr->sa_family != AF_INET) {
            continue;
        }
        if (strcmp(ifa->ifa_name, bsdName.UTF8String) != 0) {
            continue;
        }
        char buf[INET_ADDRSTRLEN] = {0};
        struct sockaddr_in *sin = (struct sockaddr_in *)ifa->ifa_addr;
        if (inet_ntop(AF_INET, &sin->sin_addr, buf, sizeof(buf))) {
            result = [NSString stringWithUTF8String:buf];
            break;
        }
    }
    freeifaddrs(ifap);
    return result;
}

#pragma mark - Wi‑Fi

- (void)buildWiFiTitle:(NSString **)title tooltip:(NSString **)tooltip copyValue:(NSString **)copyValue state:(HITPluginTestState *)state hidden:(BOOL *)hidden {
    CWInterface *iface = [[CWWiFiClient sharedWiFiClient] interface];
    if (!iface || !iface.powerOn) {
        *title = @"Wi‑Fi: Off";
        *copyValue = @"";
        *hidden = NO;
        *state = HITPluginTestStateUnavailable;
        *tooltip = @"Wi‑Fi interface is powered off";
        return;
    }
    if (!iface.serviceActive) {
        *title = @"Wi‑Fi: Not connected";
        *copyValue = @"";
        *hidden = NO;
        *state = HITPluginTestStateUnavailable;
        *tooltip = @"Wi‑Fi is on but not associated with a network";
        return;
    }

    NSString *ssid = iface.ssid;
    NSInteger rssi = iface.rssiValue;
    double txRate = iface.transmitRate;
    NSInteger noise = iface.noiseMeasurement;
    NSInteger snr = (rssi != 0 || noise != 0) ? (rssi - noise) : 0;
    NSString *bssid = iface.bssid ?: @"—";
    NSString *channel = iface.wlanChannel ? [NSString stringWithFormat:@"%ld", (long)iface.wlanChannel.channelNumber] : @"—";

    // Compact title: SNR + Tx rate (and SSID when Location allows it).
    NSString *speedPart = (txRate > 0)
        ? [NSString stringWithFormat:@", %.0f Mbps", txRate]
        : @"";
    if (ssid.length > 0) {
        *title = [NSString stringWithFormat:@"Wi‑Fi: %@ · %ld dB%@", ssid, (long)snr, speedPart];
        *copyValue = ssid;
    } else {
        *title = [NSString stringWithFormat:@"Wi‑Fi: %ld dB%@", (long)snr, speedPart];
        *copyValue = [NSString stringWithFormat:@"%ld dB%@", (long)snr, speedPart];
    }
    *hidden = NO;

    if (snr >= self.wifiWarnBelowSNR) {
        *state = HITPluginTestStateOK;
    } else if (snr >= self.wifiErrorBelowSNR) {
        *state = HITPluginTestStateWarning;
    } else {
        *state = HITPluginTestStateError;
    }

    *tooltip = [NSString stringWithFormat:@"SSID: %@\nBSSID: %@\nSNR: %ld dB\nRSSI: %ld dBm\nNoise: %ld dBm\nTx Rate: %.0f Mbps\nChannel: %@\nOK ≥ %ld dB · Warn < %ld · Error < %ld\nClick to copy",
                ssid.length ? ssid : @"—",
                bssid,
                (long)snr,
                (long)rssi,
                (long)noise,
                txRate,
                channel,
                (long)self.wifiWarnBelowSNR,
                (long)self.wifiWarnBelowSNR,
                (long)self.wifiErrorBelowSNR];
}

#pragma mark - Ethernet

- (void)buildEthernetTitle:(NSString **)title tooltip:(NSString **)tooltip copyValue:(NSString **)copyValue state:(HITPluginTestState *)state hidden:(BOOL *)hidden {
    NSDictionary *active = [self activeEthernetInfoPreferringBSD:self.interface];
    if (!active) {
        *title = @"Ethernet: Inactive";
        *copyValue = @"";
        *hidden = YES; // only show when an Ethernet link is active
        *state = HITPluginTestStateNone;
        *tooltip = @"No active Ethernet link";
        return;
    }

    NSString *bsd = active[@"bsd"] ?: @"en";
    NSNumber *speedMbps = active[@"speed"];
    NSString *ip = active[@"ip"] ?: @"";

    NSString *speedText = @"—";
    if (speedMbps && [speedMbps integerValue] > 0) {
        NSInteger mbps = [speedMbps integerValue];
        if (mbps >= 1000) {
            double gbps = mbps / 1000.0;
            if (fabs(gbps - round(gbps)) < 0.05) {
                speedText = [NSString stringWithFormat:@"%.0f Gbps", gbps];
            } else {
                speedText = [NSString stringWithFormat:@"%.1f Gbps", gbps];
            }
        } else {
            speedText = [NSString stringWithFormat:@"%ld Mbps", (long)mbps];
        }
    }

    *title = [NSString stringWithFormat:@"Ethernet: %@", speedText];
    *copyValue = speedText;
    *hidden = NO;
    *state = HITPluginTestStateOK;
    *tooltip = [NSString stringWithFormat:@"Interface: %@\nLink speed: %@\nIP: %@\nClick to copy speed",
                bsd, speedText, ip.length ? ip : @"—"];
}

- (NSDictionary *)activeEthernetInfoPreferringBSD:(NSString *)preferred {
    CFArrayRef list = SCNetworkInterfaceCopyAll();
    if (!list) {
        return nil;
    }

    NSMutableArray *candidates = [NSMutableArray array];
    CFIndex count = CFArrayGetCount(list);
    for (CFIndex i = 0; i < count; i++) {
        SCNetworkInterfaceRef iface = CFArrayGetValueAtIndex(list, i);
        CFStringRef type = SCNetworkInterfaceGetInterfaceType(iface);
        if (!type || !CFEqual(type, kSCNetworkInterfaceTypeEthernet)) {
            // Also accept Thunderbolt Ethernet / USB Ethernet style interfaces exposed as Ethernet.
            continue;
        }

        NSString *bsd = (__bridge NSString *)SCNetworkInterfaceGetBSDName(iface);
        if (bsd.length == 0) {
            continue;
        }

        // Require a live Ethernet link (IFM_ACTIVE), not just IFF_UP.
        NSInteger speed = [self ethernetLinkSpeedMbpsForBSDName:bsd];
        if (speed < 0) {
            continue;
        }

        NSString *ip = [self ipv4AddressForBSDName:bsd] ?: @"";
        NSString *display = (__bridge NSString *)SCNetworkInterfaceGetLocalizedDisplayName(iface) ?: bsd;
        NSDictionary *info = @{
            @"bsd": bsd,
            @"speed": @(speed),
            @"ip": ip,
            @"display": display
        };
        [candidates addObject:info];
    }
    CFRelease(list);

    if (candidates.count == 0) {
        return nil;
    }

    if (preferred.length > 0) {
        for (NSDictionary *info in candidates) {
            if ([info[@"bsd"] isEqualToString:preferred]) {
                return info;
            }
        }
    }

    // Prefer the primary interface if it is Ethernet.
    NSString *primary = [self primaryBSDInterface];
    if (primary.length > 0) {
        for (NSDictionary *info in candidates) {
            if ([info[@"bsd"] isEqualToString:primary]) {
                return info;
            }
        }
    }

    return candidates.firstObject;
}

/// Returns link speed in Mbps, or -1 if the interface has no active Ethernet link.
- (NSInteger)ethernetLinkSpeedMbpsForBSDName:(NSString *)bsdName {
    if (bsdName.length == 0 || bsdName.length >= IFNAMSIZ) {
        return -1;
    }

    int sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        return -1;
    }

    struct ifmediareq ifmr;
    memset(&ifmr, 0, sizeof(ifmr));
    strlcpy(ifmr.ifm_name, bsdName.UTF8String, sizeof(ifmr.ifm_name));

    if (ioctl(sock, SIOCGIFMEDIA, &ifmr) < 0) {
        close(sock);
        return -1;
    }
    close(sock);

    if ((ifmr.ifm_status & IFM_AVALID) && !(ifmr.ifm_status & IFM_ACTIVE)) {
        return -1;
    }
    if (IFM_TYPE(ifmr.ifm_active) != IFM_ETHER) {
        return -1;
    }

    switch (IFM_SUBTYPE(ifmr.ifm_active)) {
        case IFM_10_T: return 10;
        case IFM_100_TX: return 100;
        case IFM_1000_T: return 1000;
        case IFM_2500_T: return 2500;
        case IFM_10G_T:
        case IFM_10G_SR:
        case IFM_10G_LR:
        case IFM_10G_CX4:
        case IFM_10G_KR:
        case IFM_10G_KX4:
        case IFM_10G_CR1:
        case IFM_10G_ER:
            return 10000;
        default:
            // Link is active but subtype unknown — still treat as active at 0 so UI can show interface.
            return 0;
    }
}

#pragma mark - Storage

- (void)buildStorageTitle:(NSString **)title tooltip:(NSString **)tooltip copyValue:(NSString **)copyValue state:(HITPluginTestState *)state {
    // Prefer the Data volume — `/` is often the sealed system snapshot.
    NSURL *volumeURL = [NSURL fileURLWithPath:@"/System/Volumes/Data" isDirectory:YES];
    if (![[NSFileManager defaultManager] fileExistsAtPath:volumeURL.path]) {
        volumeURL = [NSURL fileURLWithPath:@"/" isDirectory:YES];
    }

    NSError *error = nil;
    NSDictionary *values = [volumeURL resourceValuesForKeys:@[
        NSURLVolumeTotalCapacityKey,
        NSURLVolumeAvailableCapacityKey,
        NSURLVolumeAvailableCapacityForImportantUsageKey,
        NSURLVolumeAvailableCapacityForOpportunisticUsageKey
    ] error:&error];

    if (!values || error) {
        *title = @"Storage: Unavailable";
        *copyValue = @"";
        *state = HITPluginTestStateUnavailable;
        *tooltip = error.localizedDescription ?: @"Unable to read volume capacity";
        return;
    }

    long long total = [values[NSURLVolumeTotalCapacityKey] longLongValue];
    long long available = [values[NSURLVolumeAvailableCapacityKey] longLongValue];
    long long important = [values[NSURLVolumeAvailableCapacityForImportantUsageKey] longLongValue];
    long long opportunistic = [values[NSURLVolumeAvailableCapacityForOpportunisticUsageKey] longLongValue];

    // Free = currently free space (AvailableCapacity).
    // Purgeable ≈ ImportantUsage − Available when Important is larger (space reclaimable by purging).
    // Fallback: Opportunistic − Important on older layouts where that delta is positive.
    long long freeBytes = available > 0 ? available : (important > 0 ? important : 0);
    long long purgeableBytes = 0;
    if (important > available && available >= 0) {
        purgeableBytes = important - available;
    } else if (opportunistic > important && important >= 0) {
        purgeableBytes = opportunistic - important;
    }

    NSString *freeText = [self formatBytes:freeBytes];
    NSString *purgeableText = [self formatBytes:purgeableBytes];
    NSString *totalText = [self formatBytes:total];
    NSString *importantText = [self formatBytes:important > 0 ? important : freeBytes];

    *title = [NSString stringWithFormat:@"Storage: %@ free · %@ purge", freeText, purgeableText];
    *copyValue = [NSString stringWithFormat:@"%@ free, %@ purgeable", freeText, purgeableText];

    // Thresholds on currently free space (decimal GB).
    long long warnBelowBytes = (long long)self.storageWarnBelowGB * 1000LL * 1000LL * 1000LL;
    long long errorBelowBytes = (long long)self.storageErrorBelowGB * 1000LL * 1000LL * 1000LL;
    if (freeBytes < errorBelowBytes) {
        *state = HITPluginTestStateError;
    } else if (freeBytes < warnBelowBytes) {
        *state = HITPluginTestStateWarning;
    } else {
        *state = HITPluginTestStateOK;
    }

    double usedRatio = 0;
    if (total > 0) {
        long long used = total - freeBytes;
        if (used < 0) used = 0;
        usedRatio = (double)used / (double)total;
    }
    NSInteger percentUsed = (NSInteger)llround(usedRatio * 100.0);

    *tooltip = [NSString stringWithFormat:@"Free: %@\nPurgeable: %@\nAvailable (incl. purgeable): %@\nTotal: %@\nUsed: %ld%%\nOK ≥ %ld GB · Warn < %ld GB · Error < %ld GB\nClick to copy",
                freeText, purgeableText, importantText, totalText, (long)percentUsed,
                (long)self.storageWarnBelowGB, (long)self.storageWarnBelowGB, (long)self.storageErrorBelowGB];
}

- (NSString *)formatBytes:(long long)bytes {
    if (bytes < 0) {
        bytes = 0;
    }
    // Whole units only so menu titles stay short (e.g. "187 GB" not "187.07 GB").
    static const long long kKB = 1000LL;
    static const long long kMB = 1000LL * 1000LL;
    static const long long kGB = 1000LL * 1000LL * 1000LL;
    static const long long kTB = 1000LL * 1000LL * 1000LL * 1000LL;
    long long unit;
    NSString *suffix;
    if (bytes >= kTB) {
        unit = kTB;
        suffix = @"TB";
    } else if (bytes >= kGB) {
        unit = kGB;
        suffix = @"GB";
    } else if (bytes >= kMB) {
        unit = kMB;
        suffix = @"MB";
    } else if (bytes >= kKB) {
        unit = kKB;
        suffix = @"KB";
    } else {
        return [NSString stringWithFormat:@"%lld bytes", bytes];
    }
    long long rounded = (bytes + unit / 2) / unit;
    return [NSString stringWithFormat:@"%lld %@", rounded, suffix];
}

#pragma mark - Uptime

- (void)buildUptimeTitle:(NSString **)title tooltip:(NSString **)tooltip copyValue:(NSString **)copyValue state:(HITPluginTestState *)state {
    struct timeval boottime;
    size_t size = sizeof(boottime);
    if (sysctlbyname("kern.boottime", &boottime, &size, NULL, 0) != 0 || boottime.tv_sec == 0) {
        *title = @"Uptime: Unavailable";
        *copyValue = @"";
        *state = HITPluginTestStateUnavailable;
        *tooltip = @"Unable to read kern.boottime";
        return;
    }

    NSDate *bootDate = [NSDate dateWithTimeIntervalSince1970:boottime.tv_sec];
    NSTimeInterval uptime = [[NSDate date] timeIntervalSinceDate:bootDate];
    if (uptime < 0) {
        uptime = 0;
    }

    NSInteger totalSeconds = (NSInteger)uptime;
    NSInteger days = totalSeconds / 86400;
    NSInteger hours = (totalSeconds % 86400) / 3600;
    NSInteger minutes = (totalSeconds % 3600) / 60;

    NSString *shortText;
    if (days >= 1) {
        shortText = [NSString stringWithFormat:@"%ld day%@", (long)days, days == 1 ? @"" : @"s"];
    } else if (hours >= 1) {
        shortText = [NSString stringWithFormat:@"%ldh %ldm", (long)hours, (long)minutes];
    } else {
        shortText = [NSString stringWithFormat:@"%ldm", (long)minutes];
    }

    *title = [NSString stringWithFormat:@"Uptime: %@", shortText];
    *copyValue = shortText;

    if (days >= self.uptimeErrorDays) {
        *state = HITPluginTestStateError;
    } else if (days >= self.uptimeWarnDays) {
        *state = HITPluginTestStateWarning;
    } else {
        *state = HITPluginTestStateOK;
    }

    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateStyle = NSDateFormatterMediumStyle;
    formatter.timeStyle = NSDateFormatterShortStyle;
    NSString *bootText = [formatter stringFromDate:bootDate] ?: @"—";

    *tooltip = [NSString stringWithFormat:@"Last boot: %@\nUptime: %ldd %ldh %ldm\nOK < %ld days · Warn ≥ %ld · Error ≥ %ld\nClick to copy",
                bootText,
                (long)days, (long)hours, (long)minutes,
                (long)self.uptimeWarnDays, (long)self.uptimeWarnDays, (long)self.uptimeErrorDays];
}

#pragma mark - Memory pressure

- (void)buildMemoryTitle:(NSString **)title tooltip:(NSString **)tooltip copyValue:(NSString **)copyValue state:(HITPluginTestState *)state {
    int pressureLevel = 0;
    size_t size = sizeof(pressureLevel);
    BOOL haveLevel = (sysctlbyname("kern.memorystatus_vm_pressure_level", &pressureLevel, &size, NULL, 0) == 0);

    // Activity Monitor graph ≈ 100 − kern.memorystatus_level (same as memory_pressure “free %”).
    NSInteger pressurePercent = -1;
    int availableLevel = 0;
    size_t availableSize = sizeof(availableLevel);
    if (sysctlbyname("kern.memorystatus_level", &availableLevel, &availableSize, NULL, 0) == 0
        && availableLevel >= 0 && availableLevel <= 100) {
        pressurePercent = 100 - availableLevel;
    }

    if (!haveLevel && pressurePercent < 0) {
        *title = @"Memory: Unavailable";
        *copyValue = @"";
        *state = HITPluginTestStateUnavailable;
        *tooltip = @"Unable to read memory pressure";
        return;
    }

    NSString *kernelText = @"—";
    if (haveLevel) {
        if (pressureLevel == kHITMemoryPressureCritical) {
            kernelText = @"Critical";
        } else if (pressureLevel == kHITMemoryPressureWarning) {
            kernelText = @"Warning";
        } else {
            kernelText = @"Normal";
        }
    }

    // Menu state: match Activity Monitor’s graph, not the early jetsam WARN.
    if (haveLevel && pressureLevel == kHITMemoryPressureCritical) {
        *state = HITPluginTestStateError;
    } else if (pressurePercent >= self.memoryErrorPercent) {
        *state = HITPluginTestStateError;
    } else if (pressurePercent >= self.memoryWarnPercent) {
        *state = HITPluginTestStateWarning;
    } else if (pressurePercent < 0 && haveLevel && pressureLevel == kHITMemoryPressureWarning) {
        // No percentage available — fall back to kernel WARN.
        *state = HITPluginTestStateWarning;
    } else {
        *state = HITPluginTestStateOK;
    }

    NSString *stateText;
    if (*state == HITPluginTestStateError) {
        stateText = @"Critical";
    } else if (*state == HITPluginTestStateWarning) {
        stateText = @"Warning";
    } else {
        stateText = @"Normal";
    }

    if (pressurePercent >= 0) {
        *title = [NSString stringWithFormat:@"Memory: %@ · %ld%%", stateText, (long)pressurePercent];
        *copyValue = [NSString stringWithFormat:@"%@ (%ld%%)", stateText, (long)pressurePercent];
    } else {
        *title = [NSString stringWithFormat:@"Memory: %@", stateText];
        *copyValue = stateText;
    }

    NSString *percentLine = pressurePercent >= 0
        ? [NSString stringWithFormat:@"Pressure: %ld%% (Activity Monitor scale)\n", (long)pressurePercent]
        : @"";
    *tooltip = [NSString stringWithFormat:@"%@Kernel level: %@ (%d)\nOK < %ld%% · Warn ≥ %ld%% · Error ≥ %ld%% or kernel Critical\nClick to copy",
                percentLine,
                kernelText,
                haveLevel ? pressureLevel : -1,
                (long)self.memoryWarnPercent,
                (long)self.memoryWarnPercent,
                (long)self.memoryErrorPercent];
}

@end
