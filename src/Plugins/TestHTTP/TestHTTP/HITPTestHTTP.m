//
//  HITPTestHTTP.m
//  TestHTTP
//
//  Created by Yoann Gini on 12/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPTestHTTP.h"

#import <CommonCrypto/CommonCrypto.h>
#import <asl.h>

#define kHITPTestHTTPURL @"URL"
#define kHITPTestHTTPStringToCompare @"originalString"
#define kHITPTestHTTPMode @"mode"
#define kHITPTestHTTPTimeout @"timeout"
#define kHITPTestHTTPIgnoreSystemState @"ignoreSystemState"
#define kHITPTestHTTPStatusForUnmatchingResult @"unmatchingResult"
#define kHITPTestHTTPStatusForFailedConnection @"failedConnection"

@interface HITPTestHTTP ()
@property NSURL *testPage;
@property NSString *mode;
@property NSString *originalString;
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
    asl_log(NULL, NULL, ASL_LEVEL_INFO, "System say the general network is %s.", state == YES ? "available" : "unavailable");
    
    self.generalNetworkIsAvailable = state;
    [self mainAction:self];
}

-(void)mainAction:(id)sender {
    if ((self.generalNetworkIsAvailable || self.ignoreSystemState) && self.allowedToRun) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
            asl_log(NULL, NULL, ASL_LEVEL_INFO, "Start test request to %s.", [[self.testPage absoluteString] cStringUsingEncoding:NSUTF8StringEncoding]);
            
            [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:self.testPage
                                                                      cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                                  timeoutInterval:self.timeout]
                                               queue:[NSOperationQueue mainQueue]
                                   completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                                       if (connectionError) {
                                           self.testState = self.failedConnection;
                                           asl_log(NULL, NULL, ASL_LEVEL_INFO, "Connection error during test.");
                                           asl_log(NULL, NULL, ASL_LEVEL_DEBUG, "%s", [[connectionError description] cStringUsingEncoding:NSUTF8StringEncoding]);
                                       } else {
                                           if ([self.mode isEqualToString:@"compare"]) {
                                               NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                               if ([content isEqualToString:self.originalString]) {
                                                   self.testState = HITPluginTestStateOK;
                                                   asl_log(NULL, NULL, ASL_LEVEL_INFO, "Data based comparaison match.");
                                               } else {
                                                   self.testState = self.unmatchingResult;
                                                   asl_log(NULL, NULL, ASL_LEVEL_INFO, "Data based comparaison didn't match.");
                                               }
                                           } else if ([self.mode isEqualToString:@"contain"]) {
                                               NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                               if ([content rangeOfString:self.originalString].location != NSNotFound) {
                                                   self.testState = HITPluginTestStateOK;
                                                   asl_log(NULL, NULL, ASL_LEVEL_INFO, "Content based comparaison match.");
                                               } else {
                                                   self.testState = self.unmatchingResult;
                                                   asl_log(NULL, NULL, ASL_LEVEL_INFO, "Content based comparaison didn't match.");
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
                                                   asl_log(NULL, NULL, ASL_LEVEL_INFO, "MD5 based comparaison match.");
                                               } else {
                                                   self.testState = self.unmatchingResult;
                                                   asl_log(NULL, NULL, ASL_LEVEL_INFO, "MD5 based comparaison didn't match.");
                                               }
                                           }
                                       }
                                   }];
        });
    }
    else {
        self.testState = HITPluginTestStateUnavailable;
        asl_log(NULL, NULL, ASL_LEVEL_INFO, "System say general network is unavailable, so we can't test anything on our side.");
    }
}

@end
