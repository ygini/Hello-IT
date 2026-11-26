//
//  HITPTestHTTP.m
//  TestHTTP
//
//  Created by Yoann Gini on 12/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPTestHTTP.h"

#import <CommonCrypto/CommonCrypto.h>
#import <os/log.h>

#define kHITPTestHTTPURL @"URL"
#define kHITPTestHTTPStringToCompare @"originalString"
#define kHITPTestHTTPMode @"mode"
#define kHITPTestHTTPTimeout @"timeout"
#define kHITPTestHTTPIgnoreSystemState @"ignoreSystemState"
#define kHITPTestHTTPStatusForUnmatchingResult @"unmatchingResult"
#define kHITPTestHTTPStatusForFailedConnection @"failedConnection"
#define kHITPTestHTTPFailoverHost @"failoverHost"

static NSString * const kHITPTestHTTPDefaultFailoverHost = @"cloudflare.com";

@interface HITPTestHTTP ()
@property NSURL *testPage;
@property NSString *mode;
@property NSString *originalString;
@property NSString *failoverHost;
@property NSInteger timeout;
@property BOOL generalNetworkIsAvailable;
@property BOOL ignoreSystemState;
@property HITPluginTestState unmatchingResult;
@property HITPluginTestState failedConnection;
@end


@implementation HITPTestHTTP


- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _testPage = [NSURL URLWithString:[settings objectForKey:kHITPTestHTTPURL]];
        _mode = [settings objectForKey:kHITPTestHTTPMode];
        _originalString = [settings objectForKey:kHITPTestHTTPStringToCompare];
        
        _ignoreSystemState = [[settings objectForKey:kHITPTestHTTPIgnoreSystemState] boolValue];

        id failoverRaw = [settings objectForKey:kHITPTestHTTPFailoverHost];
        if (failoverRaw == nil) {
            _failoverHost = kHITPTestHTTPDefaultFailoverHost;
        } else if ([failoverRaw isKindOfClass:[NSString class]]) {
            _failoverHost = [(NSString *)failoverRaw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else {
            _failoverHost = kHITPTestHTTPDefaultFailoverHost;
        }
        
        self.unmatchingResult = HITPluginTestStateWarning;
        self.failedConnection = HITPluginTestStateError;
        
        for (NSString *property in @[kHITPTestHTTPStatusForUnmatchingResult, kHITPTestHTTPStatusForFailedConnection]) {
            NSString *value = [settings objectForKey:property];
            if ([[value lowercaseString] isEqualToString:[@"HITPluginTestStateError" lowercaseString]]) {
                [self setValue:[NSNumber numberWithInt:HITPluginTestStateError] forKey:property];
                
            } else if ([[value lowercaseString] isEqualToString:[@"HITPluginTestStateWarning" lowercaseString]]) {
                [self setValue:[NSNumber numberWithInt:HITPluginTestStateWarning] forKey:property];
                
            } else if ([[value lowercaseString] isEqualToString:[@"HITPluginTestStateOK" lowercaseString]]) {
                [self setValue:[NSNumber numberWithInt:HITPluginTestStateOK] forKey:property];
                
            } else if ([[value lowercaseString] isEqualToString:[@"HITPluginTestStateUnavailable" lowercaseString]]) {
                [self setValue:[NSNumber numberWithInt:HITPluginTestStateUnavailable] forKey:property];
                
            } else if ([[value lowercaseString] isEqualToString:[@"HITPluginTestStateNone" lowercaseString]]) {
                [self setValue:[NSNumber numberWithInt:HITPluginTestStateNone] forKey:property];
                
            }
        }
        
        NSNumber *timeout = [settings objectForKey:kHITPTestHTTPTimeout];
        if (timeout) {
            _timeout = [timeout integerValue];
        } else {
            _timeout = 30;
        }
    }
    return self;
}


-(void)periodicAction:(NSTimer *)timer {
    [self mainAction:timer];
}

- (BOOL)isNetworkRelated {
    return YES;
}

- (void)generalNetworkStateUpdate:(BOOL)state {
    os_log_info(OS_LOG_DEFAULT, "System say the general network is %s.", state == YES ? "available" : "unavailable");
    
    self.generalNetworkIsAvailable = state;
    [self mainAction:self];
}

/// ICMP ping of failoverHost. Returns YES if at least one reply is received.
- (BOOL)pingFailoverHost {
    if (self.failoverHost.length == 0) {
        return NO;
    }

    NSTask *task = [[NSTask alloc] init];
    task.executableURL = [NSURL fileURLWithPath:@"/sbin/ping"];
    // -c 1 one probe; -W 2000 wait up to 2s for the reply (ms on modern macOS ping).
    task.arguments = @[@"-c", @"1", @"-W", @"2000", self.failoverHost];
    task.standardOutput = [NSPipe pipe];
    task.standardError = [NSPipe pipe];

    NSError *error = nil;
    if (![task launchAndReturnError:&error]) {
        os_log_error(OS_LOG_DEFAULT, "Failover ping failed to launch: %s",
                     [[error localizedDescription] cStringUsingEncoding:NSUTF8StringEncoding]);
        return NO;
    }
    [task waitUntilExit];
    BOOL ok = (task.terminationStatus == 0);
    os_log_info(OS_LOG_DEFAULT, "Failover ping to %s %s.",
                [self.failoverHost cStringUsingEncoding:NSUTF8StringEncoding],
                ok ? "succeeded" : "failed");
    return ok;
}

- (void)applyConnectionFailureWithFailover {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        BOOL failoverOK = [self pingFailoverHost];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!self.allowedToRun) {
                return;
            }
            if (failoverOK) {
                // Network is up, but the monitored HTTP URL still failed — warn, don't show OK.
                self.testState = HITPluginTestStateWarning;
                os_log(OS_LOG_DEFAULT, "Primary HTTP test failed; failover ping to %s succeeded — marking Warning.",
                       [self.failoverHost cStringUsingEncoding:NSUTF8StringEncoding]);
            } else {
                self.testState = self.failedConnection;
                os_log_info(OS_LOG_DEFAULT, "Primary HTTP test and failover ping both failed.");
            }
        });
    });
}

- (void)evaluateSuccessfulResponseData:(NSData *)data {
    if (!self.allowedToRun) {
        return;
    }
    if ([self.mode isEqualToString:@"compare"]) {
        NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if ([content isEqualToString:self.originalString]) {
            self.testState = HITPluginTestStateOK;
            os_log_info(OS_LOG_DEFAULT, "Data based comparaison match.");
        } else {
            self.testState = self.unmatchingResult;
            os_log_info(OS_LOG_DEFAULT, "Data based comparaison didn't match.");
        }
    } else if ([self.mode isEqualToString:@"contain"]) {
        NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if ([content rangeOfString:self.originalString].location != NSNotFound) {
            self.testState = HITPluginTestStateOK;
            os_log_info(OS_LOG_DEFAULT, "Content based comparaison match.");
        } else {
            self.testState = self.unmatchingResult;
            os_log_info(OS_LOG_DEFAULT, "Content based comparaison didn't match.");
        }
    } else if ([self.mode isEqualToString:@"md5"]) {
        CC_MD5_CTX md5sum;
        CC_MD5_Init(&md5sum);

        CC_MD5_Update(&md5sum, [data bytes], (CC_LONG)[data length]);

        unsigned char digest[CC_MD5_DIGEST_LENGTH];
        CC_MD5_Final(digest, &md5sum);
        NSString *md5String = [NSString stringWithFormat: @"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                               digest[0], digest[1],
                               digest[2], digest[3],
                               digest[4], digest[5],
                               digest[6], digest[7],
                               digest[8], digest[9],
                               digest[10], digest[11],
                               digest[12], digest[13],
                               digest[14], digest[15]];

        if ([md5String isEqualToString:self.originalString]) {
            self.testState = HITPluginTestStateOK;
            os_log_info(OS_LOG_DEFAULT, "MD5 based comparaison match.");
        } else {
            self.testState = self.unmatchingResult;
            os_log_info(OS_LOG_DEFAULT, "MD5 based comparaison didn't match.");
        }
    }
}

-(void)mainAction:(id)sender {
    if ((self.generalNetworkIsAvailable || self.ignoreSystemState) && self.allowedToRun) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            os_log_info(OS_LOG_DEFAULT, "Start test request to %s.", [[self.testPage absoluteString] cStringUsingEncoding:NSUTF8StringEncoding]);
            
            NSURLSessionConfiguration *sessionConfig = [NSURLSessionConfiguration ephemeralSessionConfiguration];
            sessionConfig.timeoutIntervalForResource = self.timeout;
            sessionConfig.timeoutIntervalForRequest = self.timeout;
            
            NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfig];
            NSURLSessionDataTask *task = [session dataTaskWithRequest:[NSURLRequest requestWithURL:self.testPage
                                                                                      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                                                  timeoutInterval:self.timeout]
                                                    completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
                if (error) {
                    os_log_info(OS_LOG_DEFAULT, "Connection error during test.");
                    os_log_debug(OS_LOG_DEFAULT, "%s", [[error description] cStringUsingEncoding:NSUTF8StringEncoding]);
                    [self applyConnectionFailureWithFailover];
                } else {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self evaluateSuccessfulResponseData:data];
                    });
                }
            }];
            [task resume];
            [session finishTasksAndInvalidate];
        });
    }
    else {
        self.testState = HITPluginTestStateUnavailable;
        os_log_info(OS_LOG_DEFAULT, "System say general network is unavailable, so we can't test anything on our side.");
    }
}

@end
