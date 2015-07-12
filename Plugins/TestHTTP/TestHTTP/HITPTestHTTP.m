//
//  HITPTestHTTP.m
//  TestHTTP
//
//  Created by Yoann Gini on 12/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPTestHTTP.h"

#import <CommonCrypto/CommonCrypto.h>

#define kHITPTestHTTPTitle @"title"
#define kHITPTestHTTPURL @"URL"
#define kHITPTestHTTPStringToCompare @"originalString"
#define kHITPTestHTTPMode @"mode"
#define kHITPTestHTTPRepeat @"repeat"
#define kHITPTestHTTPTimeout @"timeout"

@interface HITPTestHTTP ()
@property NSString *title;
@property NSURL *testPage;
@property NSString *mode;
@property NSString *originalString;
@property NSNumber *repeat;
@property HITPluginTestState testState;
@property NSTimer *cron;
@property NSMenuItem *menuItem;
@property NSInteger timeout;
@end


@implementation HITPTestHTTP

+ (id<HITPluginProtocol>)newPlugInInstanceWithSettings:(NSDictionary*)settings {
    id instance = [[self alloc] initWithSettings:settings];
    return instance;
}

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super init];
    if (self) {
        _title = [settings objectForKey:kHITPTestHTTPTitle];
        _testPage = [NSURL URLWithString:[settings objectForKey:kHITPTestHTTPURL]];
        _mode = [settings objectForKey:kHITPTestHTTPMode];
        _originalString = [settings objectForKey:kHITPTestHTTPStringToCompare];
        _repeat = [settings objectForKey:kHITPTestHTTPRepeat];
        
        _menuItem = [[NSMenuItem alloc] initWithTitle:self.title
                                               action:@selector(runTheTest:)
                                        keyEquivalent:@""];
        _menuItem.target = self;
        [_menuItem setState:NSMixedState];
        
        NSNumber *timeout = [settings objectForKey:kHITPTestHTTPTimeout];
        if (timeout) {
            _timeout = [timeout integerValue];
        } else {
            _timeout = 30;
        }
        
        
        if ([_repeat intValue] > 0) {
            _cron = [NSTimer scheduledTimerWithTimeInterval:[_repeat integerValue]
                                                     target:self
                                                   selector:@selector(runTheTest:)
                                                   userInfo:nil
                                                    repeats:YES];
            
            [_cron fire];
        } else {
            [self runTheTest];
        }
    }
    return self;
}

- (void)updateMenuItemState {
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (self.testState) {
            case HITPluginTestStateRed:
                self.menuItem.state = NSOffState;
                break;
            case HITPluginTestStateGreen:
                self.menuItem.state = NSOnState;
                break;
            case HITPluginTestStateOrange:
            default:
                self.menuItem.state = NSMixedState;
                break;
        }
    });
}

- (void)runTheTest:(id)sender {
    [self runTheTest];
}

- (void)runTheTest {
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
                                   
                                   [self updateMenuItemState];
                               }];
        
    });
}

@end
