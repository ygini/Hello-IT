//
//  HITAdvancedPlugin.m
//  HITDevKit
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import "HITAdvancedPlugin.h"
#import <os/log.h>

@interface HITAdvancedPlugin () {
    HITPluginTestState _testState;
}
@property id<HITPluginsManagerProtocol> pluginsManager;
@property (nonatomic, copy) NSString *baseMenuTitle;
/// Set during prepareNewMenuItem so chrome updates never re-enter -[HITBasicPlugin menuItem].
@property (nonatomic, weak) NSMenuItem *appliedMenuItem;
@end

@implementation HITAdvancedPlugin

@dynamic testState;

#pragma mark - Colors / images

- (NSColor *)colorForTestState:(HITPluginTestState)state {
    switch (state) {
        case HITPluginTestStateOK:
            return [NSColor systemGreenColor];
        case HITPluginTestStateWarning:
            return [NSColor systemOrangeColor];
        case HITPluginTestStateError:
            return [NSColor systemRedColor];
        case HITPluginTestStateUnavailable:
            return [NSColor systemGrayColor];
        case HITPluginTestStateNone:
        default:
            return nil;
    }
}

- (NSImage *)drawnImageForTestState:(HITPluginTestState)state {
    NSColor *color = [self colorForTestState:state];
    if (!color) {
        return nil;
    }

    BOOL warning = (state == HITPluginTestStateWarning);
    NSImage *image = [NSImage imageWithSize:NSMakeSize(16, 16) flipped:NO drawingHandler:^BOOL(NSRect dstRect) {
        [color set];
        if (warning) {
            NSBezierPath *triangle = [NSBezierPath bezierPath];
            [triangle moveToPoint:NSMakePoint(NSMidX(dstRect), NSMaxY(dstRect) - 2)];
            [triangle lineToPoint:NSMakePoint(NSMaxX(dstRect) - 2, NSMinY(dstRect) + 2)];
            [triangle lineToPoint:NSMakePoint(NSMinX(dstRect) + 2, NSMinY(dstRect) + 2)];
            [triangle closePath];
            [triangle fill];
        } else {
            [[NSBezierPath bezierPathWithOvalInRect:NSInsetRect(dstRect, 3, 3)] fill];
        }
        return YES;
    }];
    image.template = NO;
    return image;
}

- (NSImage *)bundledTiffStateImageNamed:(NSString *)imageName {
    NSBundle *bundle = [NSBundle bundleForClass:[HITAdvancedPlugin class]];
    NSString *path = [bundle pathForResource:imageName ofType:@"tiff"];
    if (path.length == 0) {
        bundle = [NSBundle bundleWithIdentifier:@"com.github.ygini.HITDevKit"];
        path = [bundle pathForResource:imageName ofType:@"tiff"];
    }
    if (path.length == 0) {
        return nil;
    }
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:path];
    if (!image) {
        return nil;
    }
    // Keep native pixel size; menuSizedImageFromImage does Retina high-quality downsample.
    image = [image copy];
    image.template = NO;
    return image;
}

- (NSImage *)stateImageForCurrentState {
    NSString *tiffName = nil;
    switch (self.testState) {
        case HITPluginTestStateError: tiffName = @"Error"; break;
        case HITPluginTestStateOK: tiffName = @"OK"; break;
        case HITPluginTestStateWarning: tiffName = @"Warning"; break;
        case HITPluginTestStateUnavailable: tiffName = @"Unavailable"; break;
        default: break;
    }

    NSImage *image = tiffName.length ? [self bundledTiffStateImageNamed:tiffName] : nil;
    if (!image) {
        image = [self drawnImageForTestState:self.testState];
    }
    if (!image) {
        image = [self imageForMenuItem];
    }
    return image;
}

#pragma mark - Title helpers

- (NSString *)sanitizedBaseTitleFromString:(NSString *)title {
    NSString *value = title ?: @"";
    // NSTextAttachment becomes U+FFFC in .title — strip so status-bar root stays "empty".
    static unichar const kNSAttachmentCharacter = 0xFFFC;
    NSString *attachmentChar = [NSString stringWithCharacters:&kNSAttachmentCharacter length:1];
    value = [value stringByReplacingOccurrencesOfString:attachmentChar withString:@""];
    if ([value hasPrefix:@"● "] || [value hasPrefix:@"▲ "]) {
        value = [value substringFromIndex:2];
    } else if ([value hasPrefix:@"●"] || [value hasPrefix:@"▲"]) {
        value = [value substringFromIndex:1];
    }
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

- (NSAttributedString *)attributedTitleWithIndicatorForBaseTitle:(NSString *)baseTitle {
    NSColor *color = [self colorForTestState:self.testState];
    NSFont *font = [NSFont menuFontOfSize:0] ?: [NSFont systemFontOfSize:13];
    NSString *safeTitle = baseTitle ?: @"";

    if (!color) {
        return [[NSAttributedString alloc] initWithString:safeTitle
                                               attributes:@{
                                                   NSFontAttributeName: font,
                                                   NSForegroundColorAttributeName: [NSColor labelColor]
                                               }];
    }

    NSString *glyph = (self.testState == HITPluginTestStateWarning) ? @"▲" : @"●";
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:[glyph stringByAppendingString:@" "]
                                                                   attributes:@{
                                                                       NSFontAttributeName: font,
                                                                       NSForegroundColorAttributeName: color
                                                                   }]];
    [result appendAttributedString:[[NSAttributedString alloc] initWithString:safeTitle
                                                                   attributes:@{
                                                                       NSFontAttributeName: font,
                                                                       NSForegroundColorAttributeName: [NSColor labelColor]
                                                                   }]];
    return result;
}

#pragma mark - Chrome

- (NSMenuItem *)menuItemForChrome {
    if (self.appliedMenuItem) {
        return self.appliedMenuItem;
    }
    // Falls back to creating via Basic only when nothing was prepared yet.
    return self.menuItem;
}

- (void)applyMenuItemChromeToItem:(NSMenuItem *)item {
    if (!item) {
        return;
    }
    self.appliedMenuItem = item;

    NSString *baseTitle = self.baseMenuTitle;
    if (baseTitle.length == 0) {
        baseTitle = [self sanitizedBaseTitleFromString:item.title];
    }
    self.baseMenuTitle = baseTitle;

    // Empty-title items are the status-bar root (icon only). Never put a state
    // glyph/image on them — AppDelegate draws the menu-bar icon separately.
    if (baseTitle.length == 0) {
        item.attributedTitle = nil;
        item.title = @"";
        item.image = nil;
        [self applyResolvedTooltipToMenuItem:item];
        return;
    }

    // Attachment-based accessories (status menus ignore NSMenuItem.image).
    // OK/Warning/Error/Unavailable → HITDevKit TIFF state icons; None → item glyph/custom image.
    if (self.testState == HITPluginTestStateNone) {
        [self applyAccessoryImage:[self imageForMenuItem] toMenuItem:item keepingTitle:baseTitle];
    } else {
        // Solid circles read larger than app icons at the same pt — use 13pt to match MSC.
        [self applyAccessoryImage:[self stateImageForCurrentState]
                       toMenuItem:item
                    keepingTitle:baseTitle
                       pointSize:13
                         yOffset:0.5];
    }
}

- (void)updateMenuItemState {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self applyMenuItemChromeToItem:[self menuItemForChrome]];
    });
}

- (void)refreshMenuItemAppearance {
    // Prefer full chrome (state TIFF or item glyph) over SimplePlugin’s accessory-only refresh.
    [self applyMenuItemChromeToItem:[self menuItemForChrome]];
}

- (void)setMenuTitle:(NSString *)title {
    self.baseMenuTitle = [self sanitizedBaseTitleFromString:title];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self applyMenuItemChromeToItem:[self menuItemForChrome]];
    });
}

-(void)sendNotificationWithMessage:(NSString*)message {
    NSString *title = self.baseMenuTitle.length ? self.baseMenuTitle : [self menuItemForChrome].title;
    [self.pluginsManager sendNotificationWithTitle:title andMessage:message from:self];
}

-(HITPluginTestState)testState {
    return _testState;
}

-(void)setTestState:(HITPluginTestState)testState {
    if (_testState == testState) {
        return;
    }
    _testState = testState;
    dispatch_async(dispatch_get_main_queue(), ^{
        [self applyMenuItemChromeToItem:[self menuItemForChrome]];

        NSString *notificationMessage = nil;
        switch (self.testState) {
            case HITPluginTestStateError:
                notificationMessage = [self localizedString:[self.settings objectForKey:kHITNotificationMessageForErrorKey]];
                break;
            case HITPluginTestStateOK:
                notificationMessage = [self localizedString:[self.settings objectForKey:kHITNotificationMessageForOKKey]];
                break;
            case HITPluginTestStateWarning:
                notificationMessage = [self localizedString:[self.settings objectForKey:kHITNotificationMessageForWarningKey]];
                break;
            case HITPluginTestStateUnavailable:
                notificationMessage = [self localizedString:[self.settings objectForKey:kHITNotificationMessageForUnavailableKey]];
                break;
            case HITPluginTestStateNone:
            default:
                notificationMessage = [self localizedString:[self.settings objectForKey:kHITNotificationMessageForNoneKey]];
                break;
        }
        if (notificationMessage) {
            [self sendNotificationWithMessage:notificationMessage];
        }
    });
}

- (NSMenuItem *)prepareNewMenuItem {
    NSMenuItem *item = [super prepareNewMenuItem];
    self.baseMenuTitle = [self sanitizedBaseTitleFromString:item.title];
    // Apply to the local item — never call self.menuItem here (stack overflow).
    [self applyMenuItemChromeToItem:item];
    return item;
}

- (instancetype)initWithSettings:(NSDictionary*)settings
{
    self = [super initWithSettings:settings];
    if (self) {
        _skipForGlobalState = [[settings objectForKey:kHITAdvancedPluginSkipForGlobalStateKey] boolValue];
    }
    return self;
}

@end
