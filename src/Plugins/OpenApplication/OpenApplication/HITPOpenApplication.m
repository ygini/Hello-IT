//
//  HITPOpenApplication.m
//  OpenApplication
//
//  Created by Yoann Gini on 16/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITPOpenApplication.h"

#define kHITPOpenApplicationName @"app"
#define kHITPOpenApplicationFileToOpen @"file"

#define kHITPOpenApplicationURL @"appURL"
#define kHITPOpenApplicationArgsArray @"args"

#define kHITPOpenApplicationHideIfNotAvailable @"hideIfNotAvailable"

#import <Cocoa/Cocoa.h>
#import <os/log.h>

@interface HITPOpenApplication ()
@property NSString *application;
@property NSString *file;

@property NSURL *appURL;
@property NSArray *args;

@property BOOL hideIfNotAvailable;
@property (strong) id menuTrackingObserver;

@end

@implementation HITPOpenApplication

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _application = [settings objectForKey:kHITPOpenApplicationName];
        _file = [[settings objectForKey:kHITPOpenApplicationFileToOpen] stringByExpandingTildeInPath];
        _hideIfNotAvailable = [[settings objectForKey:kHITPOpenApplicationHideIfNotAvailable] boolValue];
        
        NSString *appPath = [settings objectForKey:kHITPOpenApplicationURL];
        if (appPath) {
            _appURL = [NSURL fileURLWithPath:appPath];
            _args = [settings objectForKey:kHITPOpenApplicationArgsArray];
            
            if (!_args) {
                _args = @[];
            }
        }
        
        [self hideItemIfNeeded];

        if (_hideIfNotAvailable) {
            __weak typeof(self) weakSelf = self;
            _menuTrackingObserver = [[NSNotificationCenter defaultCenter]
                addObserverForName:NSMenuDidBeginTrackingNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification * _Nonnull note) {
                typeof(self) strongSelf = weakSelf;
                if (!strongSelf || !strongSelf.menuItem) {
                    return;
                }
                NSMenu *tracked = note.object;
                if (![tracked isKindOfClass:[NSMenu class]]) {
                    return;
                }
                BOOL relevant = NO;
                for (NSMenu *menu = strongSelf.menuItem.menu; menu != nil; menu = menu.supermenu) {
                    if (menu == tracked) {
                        relevant = YES;
                        break;
                    }
                }
                if (!relevant) {
                    return;
                }
                [strongSelf hideItemIfNeeded];
            }];
        }
    }
    return self;
}

- (void)stopAndPrepareForRelease {
    if (self.menuTrackingObserver) {
        [[NSNotificationCenter defaultCenter] removeObserver:self.menuTrackingObserver];
        self.menuTrackingObserver = nil;
    }
    [super stopAndPrepareForRelease];
}

- (NSString *)resolvedApplicationPath {
    if (self.application.length > 0) {
        NSString *lsPath = [[NSWorkspace sharedWorkspace] fullPathForApplication:self.application];
        if (lsPath.length > 0) {
            return lsPath;
        }
        // Newer macOS: fullPathForApplication can miss QuickSupport-style helpers.
        for (NSString *dir in @[@"/Applications", @"/Applications/Utilities", @"/System/Applications", @"/System/Applications/Utilities"]) {
            NSString *candidate = [[dir stringByAppendingPathComponent:self.application] stringByAppendingPathExtension:@"app"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
                return candidate;
            }
        }
        return nil;
    }
    if (self.appURL.path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:self.appURL.path]) {
        return self.appURL.path;
    }
    return nil;
}

- (NSImage *)imageForMenuItem {
    if ([[self.settings objectForKey:kHITSimplePluginNoIconKey] boolValue]) {
        return nil;
    }
    // Explicit imageBaseName / imagePath win when set.
    NSImage *custom = [self customImageForMenuItem];
    if (custom) {
        return custom;
    }

    NSString *appPath = [self resolvedApplicationPath];
    if (appPath.length > 0) {
        NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:appPath];
        if (icon) {
            return icon;
        }
    }

    // Type glyph fallback (same as other plugins).
    return [super imageForMenuItem];
}

- (void)hideItemIfNeeded {
    if (self.hideIfNotAvailable) {
        // Same resolution as the menu icon — Launch Services or on-disk fallbacks.
        BOOL available = [self resolvedApplicationPath].length > 0;
        self.menuItem.hidden = !available;
        if (self.menuItem.hidden) {
            os_log_info(OS_LOG_DEFAULT, "Menu item %s is hidden; application not found.",
                        [self.menuItem.title cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    } else {
        self.menuItem.hidden = NO;
    }
}

- (void)mainAction:(id)sender {
    NSString *resolvedPath = [self resolvedApplicationPath];
    NSURL *launchURL = resolvedPath.length > 0 ? [NSURL fileURLWithPath:resolvedPath] : self.appURL;

    if (self.application.length > 0 && self.file.length > 0) {
        // Prefer Launch Services by name when opening a document; fall back to resolved path.
        os_log_info(OS_LOG_DEFAULT, "User requested to open %s with optional file %s.",
                    [self.application cStringUsingEncoding:NSUTF8StringEncoding],
                    [self.file cStringUsingEncoding:NSUTF8StringEncoding]);
        BOOL opened = [[NSWorkspace sharedWorkspace] openFile:self.file
                                              withApplication:self.application
                                                andDeactivate:YES];
        if (!opened && launchURL) {
            NSError *error = nil;
            [[NSWorkspace sharedWorkspace] openURLs:@[[NSURL fileURLWithPath:self.file]]
                               withApplicationAtURL:launchURL
                                            options:0
                                      configuration:@{}
                                              error:&error];
            if (error) {
                os_log_error(OS_LOG_DEFAULT, "Error when opening file with resolved app:\n%s",
                             [[error description] cStringUsingEncoding:NSUTF8StringEncoding]);
            }
        }
        return;
    }

    if (launchURL) {
        os_log_info(OS_LOG_DEFAULT, "User requested to open application at path %s with optional args %s.",
                    [[launchURL absoluteString] cStringUsingEncoding:NSUTF8StringEncoding],
                    [[self.args description] cStringUsingEncoding:NSUTF8StringEncoding]);
        NSError *error = nil;
        NSDictionary *config = @{NSWorkspaceLaunchConfigurationArguments: self.args ?: @[]};
        [[NSWorkspace sharedWorkspace] launchApplicationAtURL:launchURL
                                                      options:0
                                                configuration:config
                                                        error:&error];
        if (error) {
            os_log_error(OS_LOG_DEFAULT, "Error when running app:\n%s",
                         [[error description] cStringUsingEncoding:NSUTF8StringEncoding]);
        }
    }
}

@end
