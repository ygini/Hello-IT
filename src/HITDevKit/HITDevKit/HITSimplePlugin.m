//
//  HITSimplePlugin.m
//  HITDevKit
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITSimplePlugin.h"

#import <os/log.h>

@interface HITSimplePlugin ()
@property NSString *script;
@property BOOL scriptChecked;
- (void)updateWithComputedTitle:(NSMenuItem *)menuItem;
@end

#define kHITPCustomScriptsPath @"/Library/Application Support/com.github.ygini.hello-it/CustomScripts"
#define kHITPDenyUserWritableScript @"denyUserWritableScript"

@implementation HITSimplePlugin


- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        
        if ([[settings objectForKey:kHITSimplePluginComputedTitleKey] length] > 0) {
            _script = [[NSString stringWithFormat:kHITPCustomScriptsPath] stringByAppendingPathComponent:[settings objectForKey:kHITSimplePluginComputedTitleKey]];

            os_log_info(OS_LOG_DEFAULT, "Loading script based plugin with script at path %s", [_script cStringUsingEncoding:NSUTF8StringEncoding]);
            
            if ([[NSFileManager defaultManager] fileExistsAtPath:_script]) {
                if ([[NSFileManager defaultManager] isWritableFileAtPath:_script] && [[NSUserDefaults standardUserDefaults] boolForKey:kHITPDenyUserWritableScript]) {
#ifdef DEBUG
                    _scriptChecked = YES;
#else
                    _scriptChecked = NO;
#endif
                    os_log_error(OS_LOG_DEFAULT, "Target script is writable, security restriction deny such a scenario %s", [_script cStringUsingEncoding:NSUTF8StringEncoding]);
                } else {
                    _scriptChecked = YES;
                }
            } else {
                _scriptChecked = NO;
                os_log_error(OS_LOG_DEFAULT, "Target script not accessible %s", [_script cStringUsingEncoding:NSUTF8StringEncoding]);
            }
        }
        
    }
    return self;
}

-(NSImage *)imageForMenuItem {
    NSString *imagePath = [self.settings objectForKey:kHITSimplePluginImagePathKey];
    NSString *imageBaseName = [self.settings objectForKey:kHITSimplePluginImageBaseNameKey];
    
    if ([imagePath length] == 0 && [imageBaseName length] > 0) {
        NSString *customImageBaseFolder = [NSString stringWithFormat:@"/Library/Application Support/com.github.ygini.hello-it/CustomImageForItem"];
        
        NSString *osxMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"];
        BOOL tryDark = NO;
        NSString *imageBaseNameForDark = nil;
        if ([osxMode isEqualToString:@"Dark"]) {
            tryDark = YES;
            imageBaseNameForDark = [imageBaseName stringByAppendingString:@"-dark"];
        }

        if (tryDark) {
            imagePath = [[customImageBaseFolder stringByAppendingPathComponent:imageBaseNameForDark] stringByAppendingPathExtension:@"png"];
            
            if (![[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
                os_log_info(OS_LOG_DEFAULT, "Image at path %s does not exist.", [imagePath cStringUsingEncoding:NSUTF8StringEncoding]);
                imagePath = nil;
            }
        }
        
        if ([imagePath length] == 0) {
            imagePath = [[customImageBaseFolder stringByAppendingPathComponent:imageBaseName] stringByAppendingPathExtension:@"png"];
        }

    }
    
    if (imagePath) {
        os_log_info(OS_LOG_DEFAULT, "Menu item set with image at path %s.", [imagePath cStringUsingEncoding:NSUTF8StringEncoding]);
        NSImage *accessoryImage = [[NSImage alloc] initWithContentsOfFile:imagePath];
        
        if (!accessoryImage) {
            os_log_error(OS_LOG_DEFAULT, "Impossible to load image at path %s.", [imagePath cStringUsingEncoding:NSUTF8StringEncoding]);
        }
        
        return accessoryImage;
    }

    return nil;
}

-(NSMenuItem *)prepareNewMenuItem {
    NSString *title = [self localizedString:[self.settings objectForKey:kHITSimplePluginTitleKey]];
    if (!title) {
        title = @"";
    }
    
    
    NSMenuItem *menuItem = [[NSMenuItem alloc] initWithTitle:title
                                                      action:@selector(mainAction:)
                                               keyEquivalent:@""];
    
    [self updateWithComputedTitle:menuItem];
    
    menuItem.target = self;
    
    menuItem.image = [self imageForMenuItem];
    
    return menuItem;
}

- (void)updateWithComputedTitle:(NSMenuItem *)menuItem {
    if (self.scriptChecked && self.allowedToRun) {
        os_log_info(OS_LOG_DEFAULT, "Get computed title with script %s", [self.script cStringUsingEncoding:NSUTF8StringEncoding]);
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            NSTask *task = [[NSTask alloc] init];
            [task setLaunchPath:self.script];
                        
            [task setStandardOutput:[NSPipe pipe]];
            NSFileHandle *fileToRead = [[task standardOutput] fileHandleForReading];
            
            dispatch_io_t stdoutChannel = dispatch_io_create(DISPATCH_IO_STREAM, [fileToRead fileDescriptor], dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^(int error) {
                
            });
            
            __block BOOL firstLine = YES;
            dispatch_io_read(stdoutChannel, 0, SIZE_MAX, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^(bool done, dispatch_data_t data, int error) {
                if (firstLine) {
                    firstLine = NO;
                } else {
                    return;
                }
                    
                NSData *stdoutData = (NSData *)data;
                
                NSString *stdoutString = [[NSString alloc] initWithData:stdoutData encoding:NSUTF8StringEncoding];
                
                NSArray *stdoutLines = [stdoutString componentsSeparatedByString:@"\n"];
                    menuItem.title = [stdoutLines firstObject];
            });
            
            @try {
                [task launch];
                
                [task waitUntilExit];
                
                os_log_info(OS_LOG_DEFAULT, "Script exited with code %i", [task terminationStatus]);
            } @catch (NSException *exception) {
                os_log_error(OS_LOG_DEFAULT, "Script failed to run: %s", [[exception reason] UTF8String]);
            }
        }];
    }
}

@end
