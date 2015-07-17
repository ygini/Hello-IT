//
//  HITPTestHTTP.m
//  TestHTTP
//
//  Created by Yoann Gini on 12/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPTestHTTP.h"

#import <CommonCrypto/CommonCrypto.h>

#define kHITPTestHTTPURL @"URL"
#define kHITPTestHTTPStringToCompare @"originalString"
#define kHITPTestHTTPMode @"mode"
#define kHITPTestHTTPTimeout @"timeout"

@interface HITPTestHTTP ()
@property NSURL *testPage;
@property NSString *mode;
@property NSString *originalString;
@property NSInteger timeout;
@end


@implementation HITPTestHTTP


- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _testPage = [NSURL URLWithString:[settings objectForKey:kHITPTestHTTPURL]];
        _mode = [settings objectForKey:kHITPTestHTTPMode];
        _originalString = [settings objectForKey:kHITPTestHTTPStringToCompare];

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

-(void)mainAction:(id)sender {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        
        [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:self.testPage
                                                                  cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                              timeoutInterval:self.timeout]
                                           queue:[NSOperationQueue mainQueue]
                               completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                                   if (connectionError) {
                                       self.testState = HITPluginTestStateRed;
                                   } else {
                                       if ([self.mode isEqualToString:@"compare"]) {
                                           NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                           if ([content isEqualToString:self.originalString]) {
                                               self.testState = HITPluginTestStateGreen;
                                           } else {
                                               self.testState = HITPluginTestStateOrange;
                                           }
                                       } else if ([self.mode isEqualToString:@"contain"]) {
                                           NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                           if ([content containsString:self.originalString]) {
                                               self.testState = HITPluginTestStateGreen;
                                           } else {
                                               self.testState = HITPluginTestStateOrange;
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
                                               self.testState = HITPluginTestStateGreen;
                                           } else {
                                               self.testState = HITPluginTestStateOrange;
                                           }
                                       }
                                   }
                               }];
        
    });
}

@end
