//
//  HITSimplePlugin.h
//  HITDevKit
//
//  Created by Yoann Gini on 17/07/2015.
//  Copyright (c) 2015 Yoann Gini (Open Source Project). All rights reserved.
//

#import <Foundation/Foundation.h>
#import <HITDevKit/HITBasicPlugin.h>

#define kHITSimplePluginTitleKey @"title"
#define kHITSimplePluginComputedTitleKey @"computedTitle"
#define kHITSimplePluginImagePathKey @"imagePath"
#define kHITSimplePluginImageBaseNameKey @"imageBaseName"
#define kHITSimplePluginNoIconKey @"noIcon"

@interface HITSimplePlugin : HITBasicPlugin

/// Rasterize any workspace/file icon to a menu-sized non-template image (default 16pt).
- (NSImage *)menuSizedImageFromImage:(NSImage *)source;
- (NSImage *)menuSizedImageFromImage:(NSImage *)source pointSize:(CGFloat)pointSize;

/// Apply an accessory icon via attributedTitle attachment. Status-item menus on
/// modern macOS often ignore NSMenuItem.image; attachments still draw.
/// Default point size is 16 (matches app/workspace icons). Positive yOffset moves the icon up.
- (void)applyAccessoryImage:(NSImage *)image toMenuItem:(NSMenuItem *)item keepingTitle:(NSString *)title;
- (void)applyAccessoryImage:(NSImage *)image toMenuItem:(NSMenuItem *)item keepingTitle:(NSString *)title pointSize:(CGFloat)pointSize;
- (void)applyAccessoryImage:(NSImage *)image toMenuItem:(NSMenuItem *)item keepingTitle:(NSString *)title pointSize:(CGFloat)pointSize yOffset:(CGFloat)yOffset;

/// Re-apply settings.tooltip (and accessibilityHelp) after title/chrome changes.
- (void)applyResolvedTooltipToMenuItem:(NSMenuItem *)item;

/// SF Symbol used when no imagePath / imageBaseName is set (configurator-style glyphs).
- (NSString *)fallbackSystemSymbolName;

/// Only settings.imagePath / imageBaseName — nil when unset (subclasses can layer their own defaults).
- (NSImage *)customImageForMenuItem;

@end

@interface HITSimplePlugin (MustBeDefinedInSubclass)
- (IBAction)mainAction:(id)sender;
-(NSImage *)imageForMenuItem;
@end
