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
@property (nonatomic, weak) NSMenuItem *accessoryMenuItem;
@property (nonatomic, copy) NSString *accessoryTitle;
@property (nonatomic, strong) id appearanceObserver;
- (void)updateWithComputedTitle:(NSMenuItem *)menuItem;
@end

#define kHITPCustomScriptsPath @"/Library/Application Support/com.github.ygini.hello-it/CustomScripts"
#define kHITPDenyUserWritableScript @"denyUserWritableScript"
/// Fixed attachment advance so titles line up; icon artwork may be smaller inside.
static const CGFloat kHITMenuIconSlotSize = 16.0;

@implementation HITSimplePlugin


- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        __weak typeof(self) weakSelf = self;
        _appearanceObserver = [[NSDistributedNotificationCenter defaultCenter]
            addObserverForName:@"AppleInterfaceThemeChangedNotification"
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification * _Nonnull note) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }
            // Re-rasterize glyphs / chrome for the new appearance.
            [strongSelf refreshMenuItemAppearance];
        }];

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

- (NSString *)fallbackSystemSymbolName {
    NSString *cn = NSStringFromClass([self class]);
    if ([cn containsString:@"Scripted"]) return @"terminal";
    if ([cn containsString:@"Command"]) return @"chevron.left.forwardslash.chevron.right";
    if ([cn containsString:@"OpenApplication"]) return @"app";
    if ([cn containsString:@"OpenResource"]) return @"link";
    if ([cn containsString:@"SendEmail"]) return @"envelope";
    if ([cn containsString:@"TestHTTP"]) return @"network";
    if ([cn containsString:@"Title"]) return @"text.alignleft";
    if ([cn containsString:@"Quit"]) return @"xmark.circle";
    if ([cn containsString:@"ADPass"]) return @"key";
    if ([cn containsString:@"SystemInfo"]) return @"info.circle";
    if ([cn containsString:@"Munki"]) return @"shippingbox";
    if ([cn containsString:@"SubMenu"]) return @"folder";
    if ([cn containsString:@"Cachet"]) return @"heart.text.square";
    if ([cn containsString:@"Separator"]) return nil;
    return @"circle";
}

/// Center `contentSize` inside `bounds` without stretching (aspect-fit).
static NSRect HITAspectFitRect(NSSize contentSize, NSRect bounds) {
    if (contentSize.width <= 0 || contentSize.height <= 0 ||
        bounds.size.width <= 0 || bounds.size.height <= 0) {
        return bounds;
    }
    CGFloat scale = MIN(bounds.size.width / contentSize.width,
                        bounds.size.height / contentSize.height);
    NSSize fitted = NSMakeSize(contentSize.width * scale, contentSize.height * scale);
    return NSMakeRect(NSMidX(bounds) - fitted.width / 2.0,
                      NSMidY(bounds) - fitted.height / 2.0,
                      fitted.width,
                      fitted.height);
}

- (NSImage *)systemSymbolMenuImageNamed:(NSString *)name {
    if (name.length == 0) {
        return nil;
    }
    if (@available(macOS 11.0, *)) {
        NSImage *symbol = [NSImage imageWithSystemSymbolName:name accessibilityDescription:name];
        if (!symbol) {
            return nil;
        }
        // Match OpenApplication / workspace icon footprint (~16pt slot).
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:14
                                                                                              weight:NSFontWeightMedium
                                                                                               scale:NSImageSymbolScaleMedium];
        symbol = [symbol imageWithSymbolConfiguration:config];
        symbol.template = YES;

        // Bake using the current appearance's label color. NSTextAttachment ignores
        // template tinting in status menus, so a dynamic labelColor draw is required
        // for light/dark (refreshed on AppleInterfaceThemeChangedNotification).
        // Aspect-fit into the square slot — SF Symbol metrics are rarely 1:1, and
        // drawInRect alone squashes them horizontally/vertically.
        __block NSImage *raster = nil;
        NSAppearance *appearance = NSApp.effectiveAppearance ?: [NSAppearance currentDrawingAppearance];
        [appearance performAsCurrentDrawingAppearance:^{
            NSColor *tint = [NSColor labelColor];
            NSSize symbolSize = symbol.size;
            raster = [NSImage imageWithSize:NSMakeSize(16, 16) flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
                // Inset before fit so the optical nudge cannot clip the top edge.
                NSRect fitBounds = NSInsetRect(dstRect, 0, 1.5);
                NSRect drawRect = HITAspectFitRect(symbolSize, fitBounds);
                // +0.5pt (was +1.5) — SF Symbols sat ~1px high vs menu title text.
                drawRect.origin.y += 0.5;
                [symbol drawInRect:drawRect
                          fromRect:NSZeroRect
                         operation:NSCompositingOperationSourceOver
                          fraction:1.0
                    respectFlipped:YES
                             hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
                [tint set];
                NSRectFillUsingOperation(drawRect, NSCompositingOperationSourceAtop);
                return YES;
            }];
            raster.template = NO;
        }];
        return raster;
    }
    return nil;
}

- (NSImage *)customImageForMenuItem {
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
    
    if (imagePath.length == 0) {
        return nil;
    }

    os_log_info(OS_LOG_DEFAULT, "Menu item set with image at path %s.", [imagePath cStringUsingEncoding:NSUTF8StringEncoding]);
    NSImage *accessoryImage = [[NSImage alloc] initWithContentsOfFile:imagePath];

    // Allow imagePath to point at an .app (or other file) — use its workspace icon.
    if (!accessoryImage && [[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
        accessoryImage = [[NSWorkspace sharedWorkspace] iconForFile:imagePath];
        if (accessoryImage) {
            accessoryImage = [accessoryImage copy];
            accessoryImage.size = NSMakeSize(16, 16);
        }
    }
    
    if (!accessoryImage) {
        os_log_error(OS_LOG_DEFAULT, "Impossible to load image at path %s.", [imagePath cStringUsingEncoding:NSUTF8StringEncoding]);
    }
    return accessoryImage;
}

-(NSImage *)imageForMenuItem {
    if ([[self.settings objectForKey:kHITSimplePluginNoIconKey] boolValue]) {
        return nil;
    }
    NSImage *custom = [self customImageForMenuItem];
    if (custom) {
        return custom;
    }
    return [self systemSymbolMenuImageNamed:[self fallbackSystemSymbolName]];
}

- (NSImage *)menuSizedImageFromImage:(NSImage *)source {
    return [self menuSizedImageFromImage:source pointSize:16];
}

- (NSImage *)menuSizedImageFromImage:(NSImage *)source pointSize:(CGFloat)pointSize {
    if (!source) {
        return nil;
    }
    if (pointSize < 1) {
        pointSize = 16;
    }
    // Template glyphs: already sized/baked by systemSymbolMenuImageNamed.
    if (source.template) {
        return source;
    }

    // Resample into a Retina bitmap — never rely on NSImage.size alone (that only
    // changes the logical size and looks soft when shrinking 23px TIFFs / app icons).
    // Prefer the sharpest attached display so a 1x external screen does not soften icons.
    CGFloat scale = 2.0;
    for (NSScreen *screen in [NSScreen screens]) {
        if (screen.backingScaleFactor > scale) {
            scale = screen.backingScaleFactor;
        }
    }
    NSInteger pixels = (NSInteger)llround(pointSize * scale);
    if (pixels < 1) {
        pixels = 1;
    }

    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
                             initWithBitmapDataPlanes:NULL
                             pixelsWide:pixels
                             pixelsHigh:pixels
                             bitsPerSample:8
                             samplesPerPixel:4
                             hasAlpha:YES
                             isPlanar:NO
                             colorSpaceName:NSDeviceRGBColorSpace
                             bytesPerRow:0
                             bitsPerPixel:0];
    rep.size = NSMakeSize(pointSize, pointSize);

    [NSGraphicsContext saveGraphicsState];
    NSGraphicsContext *ctx = [NSGraphicsContext graphicsContextWithBitmapImageRep:rep];
    ctx.imageInterpolation = NSImageInterpolationHigh;
    [NSGraphicsContext setCurrentContext:ctx];

    [[NSColor clearColor] set];
    NSRectFill(NSMakeRect(0, 0, pointSize, pointSize));

    NSSize sourceSize = source.size;
    if (sourceSize.width < 1 || sourceSize.height < 1) {
        // Prefer the largest pixel representation when .size is unreliable.
        for (NSImageRep *r in source.representations) {
            if (r.pixelsWide > sourceSize.width) {
                sourceSize = NSMakeSize(r.pixelsWide, r.pixelsHigh);
            }
        }
    }
    if (sourceSize.width < 1 || sourceSize.height < 1) {
        sourceSize = NSMakeSize(pointSize, pointSize);
    }

    NSRect dst = NSMakeRect(0, 0, pointSize, pointSize);
    NSRect drawRect = HITAspectFitRect(sourceSize, dst);
    [source drawInRect:drawRect
              fromRect:NSZeroRect
             operation:NSCompositingOperationSourceOver
              fraction:1.0
        respectFlipped:YES
                 hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];

    [NSGraphicsContext restoreGraphicsState];

    NSImage *img = [[NSImage alloc] initWithSize:NSMakeSize(pointSize, pointSize)];
    [img addRepresentation:rep];
    img.template = NO;
    return img;
}

- (NSString *)resolvedTooltipString {
    id tooltipValue = [self.settings objectForKey:@"tooltip"];
    if (!tooltipValue) {
        id titleValue = [self.settings objectForKey:kHITSimplePluginTitleKey];
        if ([titleValue isKindOfClass:[NSDictionary class]]) {
            tooltipValue = [titleValue objectForKey:@"tooltip"];
        }
    }
    NSString *tooltip = [self localizedString:tooltipValue];
    return tooltip.length ? tooltip : nil;
}

- (void)applyResolvedTooltipToMenuItem:(NSMenuItem *)item {
    if (!item) {
        return;
    }
    NSString *tooltip = [self resolvedTooltipString];
    // Re-apply after attributedTitle changes — status menus often drop tips otherwise.
    item.toolTip = tooltip;
    if (tooltip.length > 0) {
        item.accessibilityHelp = tooltip;
    }
}

- (void)applyAccessoryImage:(NSImage *)image toMenuItem:(NSMenuItem *)item keepingTitle:(NSString *)title {
    // 16pt matches workspace/app icons (Managed Software Centre, etc.).
    [self applyAccessoryImage:image toMenuItem:item keepingTitle:title pointSize:16 yOffset:0];
}

- (void)applyAccessoryImage:(NSImage *)image toMenuItem:(NSMenuItem *)item keepingTitle:(NSString *)title pointSize:(CGFloat)pointSize {
    [self applyAccessoryImage:image toMenuItem:item keepingTitle:title pointSize:pointSize yOffset:0];
}

- (void)applyAccessoryImage:(NSImage *)image toMenuItem:(NSMenuItem *)item keepingTitle:(NSString *)title pointSize:(CGFloat)pointSize yOffset:(CGFloat)yOffset {
    if (!item) {
        return;
    }
    if (pointSize < 1) {
        pointSize = 16;
    }
    // Strip attachment placeholder chars that attributed titles inject into .title.
    static unichar const kNSAttachmentCharacter = 0xFFFC;
    NSString *attachmentChar = [NSString stringWithCharacters:&kNSAttachmentCharacter length:1];
    NSString *safeTitle = [(title ?: @"") stringByReplacingOccurrencesOfString:attachmentChar withString:@""];
    safeTitle = [safeTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    // Also strip state glyphs if re-applying over an advanced chrome title.
    if ([safeTitle hasPrefix:@"● "] || [safeTitle hasPrefix:@"▲ "]) {
        safeTitle = [safeTitle substringFromIndex:2];
    }

    self.accessoryMenuItem = item;
    self.accessoryTitle = safeTitle;

    // Empty-title items are the status-bar root — never put a glyph there or
    // AppDelegate will treat the menu as titled and replace the status icon with a dot.
    if (safeTitle.length == 0) {
        item.attributedTitle = nil;
        item.title = @"";
        item.image = nil;
        [self applyResolvedTooltipToMenuItem:item];
        return;
    }

    NSImage *sized = [self menuSizedImageFromImage:image pointSize:pointSize];
    if (!sized) {
        item.attributedTitle = nil;
        item.title = safeTitle;
        item.image = nil;
        [self applyResolvedTooltipToMenuItem:item];
        return;
    }

    // Keep the icon's drawn size, but always advance a 16pt slot so labels share one column
    // (status TIFFs at 13pt would otherwise pull titles left of app / SF rows).
    NSImage *slotted = sized;
    if (fabs(sized.size.width - kHITMenuIconSlotSize) > 0.01 ||
        fabs(sized.size.height - kHITMenuIconSlotSize) > 0.01) {
        NSSize iconSize = sized.size;
        slotted = [NSImage imageWithSize:NSMakeSize(kHITMenuIconSlotSize, kHITMenuIconSlotSize)
                                 flipped:NO
                          drawingHandler:^BOOL(NSRect dstRect) {
            NSRect drawRect = NSMakeRect(NSMidX(dstRect) - iconSize.width / 2.0,
                                         NSMidY(dstRect) - iconSize.height / 2.0,
                                         iconSize.width,
                                         iconSize.height);
            [sized drawInRect:drawRect
                     fromRect:NSZeroRect
                    operation:NSCompositingOperationSourceOver
                     fraction:1.0
               respectFlipped:YES
                        hints:@{NSImageHintInterpolation: @(NSImageInterpolationHigh)}];
            return YES;
        }];
        slotted.template = NO;
    }

    // Status-item menus frequently drop NSMenuItem.image; NSTextAttachment still shows.
    NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
    attachment.image = slotted;
    // Negative y drops below the baseline; positive yOffset nudges the icon up.
    // Bounds width is always the slot so every title starts at the same x.
    attachment.bounds = CGRectMake(0,
                                   -(kHITMenuIconSlotSize * 0.2) + yOffset,
                                   kHITMenuIconSlotSize,
                                   kHITMenuIconSlotSize);

    NSMutableAttributedString *attr = [[NSAttributedString attributedStringWithAttachment:attachment] mutableCopy];
    NSFont *font = [NSFont menuFontOfSize:0] ?: [NSFont systemFontOfSize:13];
    // Use labelColor so title text tracks light/dark with the menu.
    [attr appendAttributedString:[[NSAttributedString alloc] initWithString:[@" " stringByAppendingString:safeTitle]
                                                                 attributes:@{
                                                                     NSFontAttributeName: font,
                                                                     NSForegroundColorAttributeName: [NSColor labelColor]
                                                                 }]];
    item.image = nil;
    item.attributedTitle = attr;
    [self applyResolvedTooltipToMenuItem:item];
}

- (void)refreshMenuItemAppearance {
    if (!self.accessoryMenuItem) {
        return;
    }
    [self applyAccessoryImage:[self imageForMenuItem]
                   toMenuItem:self.accessoryMenuItem
                keepingTitle:self.accessoryTitle ?: @""];
}

- (void)stopAndPrepareForRelease {
    if (self.appearanceObserver) {
        [[NSDistributedNotificationCenter defaultCenter] removeObserver:self.appearanceObserver];
        self.appearanceObserver = nil;
    }
    self.accessoryMenuItem = nil;
    [super stopAndPrepareForRelease];
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

    [self applyAccessoryImage:[self imageForMenuItem] toMenuItem:menuItem keepingTitle:title];
    
    return menuItem;
}

- (void)updateWithComputedTitle:(NSMenuItem *)menuItem {
    // Require a real path: subclasses must not reuse scriptChecked for unrelated flags
    // (Command previously did — Apply reloaded with setLaunchPath:nil → abort).
    if (self.scriptChecked && self.allowedToRun && self.script.length > 0) {
        os_log_info(OS_LOG_DEFAULT, "Get computed title with script %s", [self.script cStringUsingEncoding:NSUTF8StringEncoding]);
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            if (!self.allowedToRun || self.script.length == 0) {
                return;
            }

            NSTask *task = [[NSTask alloc] init];
            [task setLaunchPath:self.script];
                        
            [task setStandardOutput:[NSPipe pipe]];
            NSFileHandle *fileToRead = [[task standardOutput] fileHandleForReading];
            
            dispatch_io_t stdoutChannel = dispatch_io_create(DISPATCH_IO_STREAM, [fileToRead fileDescriptor], dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^(int error) {
                
            });
            
            // Accumulate across read callbacks — the first chunk can be empty with buffered pipes.
            __block NSMutableData *accumulated = [NSMutableData data];
            __block BOOL appliedTitle = NO;
            dispatch_io_read(stdoutChannel, 0, SIZE_MAX, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^(bool done, dispatch_data_t data, int error) {
                if (appliedTitle) {
                    return;
                }

                if (data) {
                    dispatch_data_apply(data, ^bool(dispatch_data_t region, size_t offset, const void *buffer, size_t size) {
                        if (buffer && size > 0) {
                            [accumulated appendBytes:buffer length:size];
                        }
                        return true;
                    });
                }

                NSString *stdoutString = [[NSString alloc] initWithData:accumulated encoding:NSUTF8StringEncoding] ?: @"";
                NSRange newline = [stdoutString rangeOfString:@"\n"];
                NSString *computed = nil;
                if (newline.location != NSNotFound) {
                    computed = [stdoutString substringToIndex:newline.location];
                } else if (done && stdoutString.length > 0) {
                    computed = stdoutString;
                } else {
                    return; // wait for more data (or EOF with content)
                }

                if (computed.length == 0) {
                    return;
                }
                appliedTitle = YES;

                // Assigning menuItem.title clears attributedTitle (icons/state glyphs).
                // dispatch_io callbacks run off the main queue — UI updates must hop to main.
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (!self.allowedToRun) {
                        return;
                    }
                    // HITAdvancedPlugin implements setMenuTitle: (reapplies state chrome).
                    // Avoid importing Advanced from Simple — use performSelector.
                    SEL setTitle = NSSelectorFromString(@"setMenuTitle:");
                    if ([self respondsToSelector:setTitle]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        [self performSelector:setTitle withObject:computed];
#pragma clang diagnostic pop
                    } else {
                        [self applyAccessoryImage:[self imageForMenuItem]
                                       toMenuItem:menuItem
                                    keepingTitle:computed];
                    }
                });
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
