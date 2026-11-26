//
//  HITConfiguratorController.m
//  Hello IT
//
//  Configurator Mode MVP — tree editor for Hello-IT preference content.
//

#import "HITConfiguratorController.h"
#import <os/log.h>
#import <ifaddrs.h>
#import <net/if.h>

static NSString * const kHITConfigFunctionIdentifier = @"functionIdentifier";
static NSString * const kHITConfigSettings = @"settings";
static NSString * const kHITConfigContent = @"content";
static NSString * const kHITConfigTitle = @"title";
// Bump when changing the default window size so old autosaved frames don’t stick.
static NSString * const kHITConfigWindowFrameAutosave = @"HITConfiguratorWindowFrame_v4";
static NSString * const kHITConfigOutlineDragType = @"com.github.ygini.Hello-IT.configurator.item";

static const CGFloat kHITConfigDefaultWidth = 1100;
static const CGFloat kHITConfigDefaultHeight = 720;
static const CGFloat kHITConfigMinWidth = 1000;
static const CGFloat kHITConfigMinHeight = 600;
static const CGFloat kHITConfigLeftPaneWidth = 300;
static const CGFloat kHITConfigInspectorLabelWidth = 80;
static const CGFloat kHITConfigInspectorControlX = 100;
static const CGFloat kHITConfigInspectorRightPad = 16;
static const CGFloat kHITConfigInspectorButtonSize = 28;
static const CGFloat kHITConfigInspectorButtonGap = 4;

typedef NS_ENUM(NSInteger, HITConfigIconMode) {
    HITConfigIconModeAutomatic = 0, // no keys — type glyph / app icon at runtime
    HITConfigIconModeNone = 1,      // settings.noIcon = YES — title only
    HITConfigIconModeImageName = 2, // settings.imageBaseName
    HITConfigIconModeFilePath = 3,  // settings.imagePath
};

/// Top-left origin so short inspectors don’t sit on the bottom of the scroll view.
@interface HITConfigFlippedView : NSView
@end
@implementation HITConfigFlippedView
- (BOOL)isFlipped { return YES; }
@end

/// Path field that accepts Finder file/folder drops (same values as the … browse button).
@interface HITConfigDroppableTextField : NSTextField
@property (nonatomic, copy, nullable) BOOL (^canAcceptDropPath)(NSString *path);
@property (nonatomic, copy, nullable) void (^didDropPath)(NSString *path);
@end

@implementation HITConfigDroppableTextField

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL, NSFilenamesPboardType]];
    }
    return self;
}

- (NSString *)hit_firstDroppedPathFromInfo:(id<NSDraggingInfo>)info {
    NSPasteboard *pb = [info draggingPasteboard];
    NSArray *urls = [pb readObjectsForClasses:@[[NSURL class]]
                                      options:@{ NSPasteboardURLReadingFileURLsOnlyKey: @YES }];
    if ([urls isKindOfClass:[NSArray class]] && urls.count > 0) {
        NSURL *url = urls.firstObject;
        if ([url isKindOfClass:[NSURL class]] && url.path.length > 0) {
            return url.path;
        }
    }
    NSArray *paths = [pb propertyListForType:NSFilenamesPboardType];
    if ([paths isKindOfClass:[NSArray class]] && [paths.firstObject isKindOfClass:[NSString class]]) {
        return paths.firstObject;
    }
    return nil;
}

- (NSDragOperation)hit_proposedOperationForInfo:(id<NSDraggingInfo>)info {
    if (self.isHidden || !self.isEnabled) {
        return NSDragOperationNone;
    }
    NSString *path = [self hit_firstDroppedPathFromInfo:info];
    if (path.length == 0) {
        return NSDragOperationNone;
    }
    if (self.canAcceptDropPath && !self.canAcceptDropPath(path)) {
        return NSDragOperationNone;
    }
    return NSDragOperationCopy;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    return [self hit_proposedOperationForInfo:sender];
}

- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
    return [self hit_proposedOperationForInfo:sender];
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
    return [self hit_proposedOperationForInfo:sender] != NSDragOperationNone;
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSString *path = [self hit_firstDroppedPathFromInfo:sender];
    if (path.length == 0) {
        return NO;
    }
    if (self.canAcceptDropPath && !self.canAcceptDropPath(path)) {
        return NO;
    }
    if (self.didDropPath) {
        self.didDropPath(path);
        return YES;
    }
    return NO;
}

@end

@interface HITConfiguratorController () <NSOutlineViewDataSource, NSOutlineViewDelegate, NSTextFieldDelegate, NSWindowDelegate>

@property (nonatomic, strong, nullable) id previousToolTipDelay;
@property (nonatomic, assign) BOOL didOverrideToolTipDelay;
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary *> *rootContent;
@property (nonatomic, strong) NSOutlineView *outlineView;
@property (nonatomic, strong) NSPopUpButton *typePopup;
@property (nonatomic, strong) NSTextField *titleField;
@property (nonatomic, strong) NSTextField *tooltipField;
@property (nonatomic, strong) NSPopUpButton *iconModePopup;
@property (nonatomic, strong) NSTextField *iconModeLabel;
@property (nonatomic, strong) NSTextField *iconValueField;
@property (nonatomic, strong) NSTextField *iconValueLabel;
@property (nonatomic, strong) NSTextField *iconHintLabel;
@property (nonatomic, strong) NSButton *iconBrowseButton;
@property (nonatomic, strong) NSButton *iconRevealButton;
@property (nonatomic, strong) NSTextField *keyField;   // script / URL / app / command
@property (nonatomic, strong) NSTextField *keyLabel;
@property (nonatomic, strong) NSButton *keyBrowseButton;
@property (nonatomic, strong) NSButton *keyRevealButton;
@property (nonatomic, strong) NSTextField *fileField;  // open.application file OR send.email deviceURL
@property (nonatomic, strong) NSTextField *fileLabel;
@property (nonatomic, strong) NSButton *fileBrowseButton;
@property (nonatomic, strong) NSButton *fileRevealButton;
@property (nonatomic, strong) NSTextField *optionsField; // script options OR test.http mode OR send.email subject
@property (nonatomic, strong) NSTextField *optionsLabel;
@property (nonatomic, strong) NSTextField *bodyField; // send.email body template
@property (nonatomic, strong) NSTextField *bodyLabel;
@property (nonatomic, strong) NSPopUpButton *infoKindPopup;
@property (nonatomic, strong) NSTextField *infoKindLabel;
@property (nonatomic, strong) NSPopUpButton *infoOptionPopup;
@property (nonatomic, strong) NSTextField *infoOptionLabel;
@property (nonatomic, strong) NSPopUpButton *infoInterfacePopup;
@property (nonatomic, strong) NSTextField *infoInterfaceLabel;
@property (nonatomic, strong) NSTextField *uptimeWarnField;
@property (nonatomic, strong) NSTextField *uptimeWarnLabel;
@property (nonatomic, strong) NSTextField *uptimeErrorField;
@property (nonatomic, strong) NSTextField *uptimeErrorLabel;
@property (nonatomic, strong) NSTextField *repeatField;
@property (nonatomic, strong) NSTextField *repeatLabel;
@property (nonatomic, strong) NSTextField *notificationsSectionLabel;
@property (nonatomic, strong) NSTextField *notifyHintLabel;
@property (nonatomic, strong) NSTextField *notifyOKField;
@property (nonatomic, strong) NSButton *notifyOKSwitch;
@property (nonatomic, strong) NSTextField *notifyWarningField;
@property (nonatomic, strong) NSButton *notifyWarningSwitch;
@property (nonatomic, strong) NSTextField *notifyErrorField;
@property (nonatomic, strong) NSButton *notifyErrorSwitch;
@property (nonatomic, strong) NSTextField *notifyUnavailableField;
@property (nonatomic, strong) NSButton *notifyUnavailableSwitch;
@property (nonatomic, strong) NSTextField *notifyNoneField;
@property (nonatomic, strong) NSButton *notifyNoneSwitch;
@property (nonatomic, strong) NSButton *skipGlobalCheckbox;
@property (nonatomic, strong) NSButton *optionalDisplayCheckbox;
@property (nonatomic, strong) NSButton *hideIfUnavailableCheckbox;
@property (nonatomic, strong) NSView *inspectorView;
@property (nonatomic, strong) NSScrollView *inspectorScrollView;
@property (nonatomic, strong) NSSplitView *mainSplitView;
@property (nonatomic, strong) NSTextField *itemSectionLabel;
@property (nonatomic, strong) NSTextField *iconSectionLabel;
@property (nonatomic, strong) NSTextField *actionSectionLabel;
@property (nonatomic, strong) NSTextField *behaviorSectionLabel;
@property (nonatomic, strong) NSTextField *footerHintLabel;
@property (nonatomic, strong) NSTextField *typeLabel;
@property (nonatomic, strong) NSTextField *titleLabel;
@property (nonatomic, strong) NSTextField *tooltipLabel;
@property (nonatomic, assign) CGFloat actionLayoutTopY;
@property (nonatomic, weak) NSMutableDictionary *selectedItem;
@property (nonatomic, strong) NSArray *draggedOutlineItems;
@property (nonatomic, assign) BOOL updatingUI;
@property (nonatomic, assign) BOOL suppressInspectorScrollToTop;

@end

@implementation HITConfiguratorController

+ (instancetype)sharedController {
    static HITConfiguratorController *shared;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[HITConfiguratorController alloc] init];
    });
    return shared;
}

- (instancetype)init {
    // Wide enough for left tree + inspector fields + browse/reveal + Import button.
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, kHITConfigDefaultWidth, kHITConfigDefaultHeight)
                                                   styleMask:(NSWindowStyleMaskTitled |
                                                              NSWindowStyleMaskClosable |
                                                              NSWindowStyleMaskResizable |
                                                              NSWindowStyleMaskMiniaturizable)
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"Hello IT — Configurator Mode";
    window.contentMinSize = NSMakeSize(kHITConfigMinWidth, kHITConfigMinHeight);
    window.minSize = NSMakeSize(kHITConfigMinWidth, kHITConfigMinHeight + 28);
    window.frameAutosaveName = kHITConfigWindowFrameAutosave;
    self = [super initWithWindow:window];
    if (self) {
        self.window.delegate = self;
        [self buildUI];
    }
    return self;
}

#pragma mark - Public

- (void)showConfigurator {
    // Faster hover tips while Configurator is open; restore on close (global Cocoa default).
    if (!self.didOverrideToolTipDelay) {
        self.previousToolTipDelay = [[NSUserDefaults standardUserDefaults] objectForKey:@"NSInitialToolTipDelay"];
        [[NSUserDefaults standardUserDefaults] setObject:@100 forKey:@"NSInitialToolTipDelay"];
        self.didOverrideToolTipDelay = YES;
    }

    [self ensureStandardEditMenu];
    [self loadFromDefaults];
    [self.outlineView reloadData];
    [self expandAllSubmenus];
    self.window.acceptsMouseMovedEvents = YES;
    // Restore saved frame if present; otherwise center once.
    if (![self.window setFrameUsingName:kHITConfigWindowFrameAutosave]) {
        [self.window setContentSize:NSMakeSize(kHITConfigDefaultWidth, kHITConfigDefaultHeight)];
        [self.window center];
    }
    [self ensureConfiguratorWindowFitsContent];
    [self showWindow:nil];
    [self.mainSplitView setPosition:kHITConfigLeftPaneWidth ofDividerAtIndex:0];
    if (self.outlineView.numberOfRows > 0 && self.outlineView.selectedRow < 0) {
        [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    }
    [self reflowInspectorFromIconSection];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)ensureConfiguratorWindowFitsContent {
    NSRect frame = self.window.frame;
    NSSize content = self.window.contentLayoutRect.size;
    CGFloat addW = MAX(0, kHITConfigMinWidth - content.width);
    CGFloat addH = MAX(0, kHITConfigMinHeight - content.height);
    if (addW > 0 || addH > 0) {
        frame.size.width += addW;
        frame.size.height += addH;
        [self.window setFrame:frame display:YES];
    }
}

/// LSUIElement apps have no Edit menu by default, so ⌘X/C/V never reach text fields.
- (void)ensureStandardEditMenu {
    NSMenu *mainMenu = [NSApp mainMenu];
    if (mainMenu && [mainMenu itemWithTitle:@"Edit"]) {
        return;
    }

    mainMenu = [[NSMenu alloc] initWithTitle:@"MainMenu"];

    NSMenuItem *appItem = [[NSMenuItem alloc] init];
    NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Hello IT"];
    [appMenu addItemWithTitle:@"Quit Hello IT" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;
    [mainMenu addItem:appItem];

    NSMenuItem *editItem = [[NSMenuItem alloc] init];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem *redo = [[NSMenuItem alloc] initWithTitle:@"Redo"
                                                   action:@selector(redo:)
                                            keyEquivalent:@"z"];
    redo.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItem:redo];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    editItem.submenu = editMenu;
    [mainMenu addItem:editItem];

    [NSApp setMainMenu:mainMenu];
}

- (void)windowDidResize:(NSNotification *)notification {
    [self.window saveFrameUsingName:kHITConfigWindowFrameAutosave];
    self.suppressInspectorScrollToTop = YES;
    [self reflowInspectorFromIconSection];
    self.suppressInspectorScrollToTop = NO;
}

- (void)windowDidMove:(NSNotification *)notification {
    [self.window saveFrameUsingName:kHITConfigWindowFrameAutosave];
}

- (void)windowWillClose:(NSNotification *)notification {
    if (!self.didOverrideToolTipDelay) {
        return;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (self.previousToolTipDelay) {
        [defaults setObject:self.previousToolTipDelay forKey:@"NSInitialToolTipDelay"];
    } else {
        [defaults removeObjectForKey:@"NSInitialToolTipDelay"];
    }
    self.previousToolTipDelay = nil;
    self.didOverrideToolTipDelay = NO;
}

- (void)expandAllSubmenus {
    for (NSDictionary *item in self.rootContent) {
        [self expandItemRecursive:item];
    }
}

- (void)expandItemRecursive:(id)item {
    if (![self outlineView:self.outlineView isItemExpandable:item]) {
        return;
    }
    [self.outlineView expandItem:item];
    for (id child in [self childrenOfItem:item]) {
        [self expandItemRecursive:child];
    }
}

#pragma mark - UI

- (void)buildUI {
    NSView *content = self.window.contentView;

    NSSplitView *split = [[NSSplitView alloc] initWithFrame:content.bounds];
    split.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    split.vertical = YES;
    split.dividerStyle = NSSplitViewDividerStyleThin;
    [content addSubview:split];
    self.mainSplitView = split;

    // Left: menu-preview outline + add/remove (pin chrome to fill, buttons to bottom).
    const CGFloat leftButtonBarHeight = 36;
    const CGFloat leftInset = 8;
    NSView *left = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, kHITConfigLeftPaneWidth, kHITConfigDefaultHeight)];
    left.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSRect chromeFrame = NSMakeRect(leftInset,
                                    leftButtonBarHeight,
                                    kHITConfigLeftPaneWidth - leftInset * 2,
                                    kHITConfigDefaultHeight - leftButtonBarHeight - leftInset);
    NSVisualEffectView *menuChrome = [[NSVisualEffectView alloc] initWithFrame:chromeFrame];
    // Stretch with pane; keep inset from top and gap above the button bar.
    menuChrome.autoresizingMask = (NSViewWidthSizable | NSViewHeightSizable |
                                   NSViewMinYMargin | NSViewMaxYMargin);
    menuChrome.material = NSVisualEffectMaterialMenu;
    menuChrome.blendingMode = NSVisualEffectBlendingModeBehindWindow;
    menuChrome.state = NSVisualEffectStateActive;
    menuChrome.wantsLayer = YES;
    menuChrome.layer.cornerRadius = 6;
    [left addSubview:menuChrome];

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:menuChrome.bounds];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.drawsBackground = NO;
    scroll.borderType = NSNoBorder;
    scroll.automaticallyAdjustsContentInsets = NO;
    scroll.contentInsets = NSEdgeInsetsMake(6, 4, 6, 4);

    NSTableColumn *col = [[NSTableColumn alloc] initWithIdentifier:@"item"];
    col.title = @"Menu";
    col.resizingMask = NSTableColumnAutoresizingMask;
    col.width = chromeFrame.size.width - 8;

    self.outlineView = [[NSOutlineView alloc] initWithFrame:scroll.bounds];
    self.outlineView.headerView = nil;
    [self.outlineView addTableColumn:col];
    self.outlineView.outlineTableColumn = col;
    self.outlineView.allowsMultipleSelection = NO;
    self.outlineView.dataSource = self;
    self.outlineView.delegate = self;
    self.outlineView.rowHeight = 24;
    self.outlineView.indentationPerLevel = 14;
    self.outlineView.indentationMarkerFollowsCell = YES;
    self.outlineView.backgroundColor = [NSColor clearColor];
    self.outlineView.usesAlternatingRowBackgroundColors = NO;
    self.outlineView.selectionHighlightStyle = NSTableViewSelectionHighlightStyleRegular;
    self.outlineView.intercellSpacing = NSMakeSize(0, 1);
    self.outlineView.columnAutoresizingStyle = NSTableViewLastColumnOnlyAutoresizingStyle;
    if (@available(macOS 11.0, *)) {
        self.outlineView.style = NSTableViewStylePlain;
    }
    self.outlineView.allowsEmptySelection = YES;
    self.outlineView.toolTip = @"Drag items to reorder; drop on a submenu to nest";
    [self.outlineView registerForDraggedTypes:@[kHITConfigOutlineDragType]];
    [self.outlineView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    self.outlineView.draggingDestinationFeedbackStyle = NSTableViewDraggingDestinationFeedbackStyleSourceList;
    scroll.documentView = self.outlineView;
    [menuChrome addSubview:scroll];

    // y=0 is bottom — keep the add/remove bar glued there when the window grows.
    NSButton *addButton = [self buttonWithTitle:@"+" action:@selector(addItem:) frame:NSMakeRect(leftInset, 6, 32, 24)];
    NSButton *addChildButton = [self buttonWithTitle:@"↳+" action:@selector(addChildItem:) frame:NSMakeRect(leftInset + 36, 6, 40, 24)];
    NSButton *duplicateButton = [self buttonWithTitle:@"⧉" action:@selector(duplicateItem:) frame:NSMakeRect(leftInset + 80, 6, 32, 24)];
    NSButton *removeButton = [self buttonWithTitle:@"−" action:@selector(removeItem:) frame:NSMakeRect(leftInset + 116, 6, 32, 24)];
    addButton.autoresizingMask = NSViewMaxYMargin;
    addChildButton.autoresizingMask = NSViewMaxYMargin;
    duplicateButton.autoresizingMask = NSViewMaxYMargin;
    removeButton.autoresizingMask = NSViewMaxYMargin;
    addButton.toolTip = @"Add item after selection";
    addChildButton.toolTip = @"Add child (turns item into submenu if needed)";
    duplicateButton.toolTip = @"Duplicate selected item";
    removeButton.toolTip = @"Remove selected item";
    [left addSubview:addButton];
    [left addSubview:addChildButton];
    [left addSubview:duplicateButton];
    [left addSubview:removeButton];

    // Right: scrollable inspector + fixed action bar
    CGFloat rightWidth = kHITConfigDefaultWidth - kHITConfigLeftPaneWidth;
    NSView *right = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, rightWidth, kHITConfigDefaultHeight)];
    right.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSScrollView *inspectorScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 56, rightWidth, kHITConfigDefaultHeight - 56)];
    inspectorScroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    inspectorScroll.hasVerticalScroller = YES;
    inspectorScroll.borderType = NSNoBorder;
    inspectorScroll.drawsBackground = NO;
    inspectorScroll.autohidesScrollers = YES;
    self.inspectorScrollView = inspectorScroll;

    HITConfigFlippedView *inspector = [[HITConfigFlippedView alloc] initWithFrame:NSMakeRect(0, 0, rightWidth - 20, 40)];

    self.itemSectionLabel = [self makeSectionLabel:@"Item"];
    [inspector addSubview:self.itemSectionLabel];

    self.typePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 25)];
    self.typePopup.autoresizingMask = NSViewWidthSizable;
    self.typeLabel = [self label:@"Type" at:NSMakeRect(0, 0, 80, 16)];
    [inspector addSubview:self.typeLabel];
    [inspector addSubview:self.typePopup];
    [self rebuildTypePopup];
    self.typePopup.target = self;
    self.typePopup.action = @selector(typeChanged:);

    self.titleField = [self textFieldAt:NSMakeRect(0, 0, 380, 24)];
    self.titleLabel = [self label:@"Title" at:NSMakeRect(0, 0, 80, 16)];
    [inspector addSubview:self.titleLabel];
    [inspector addSubview:self.titleField];
    self.titleField.delegate = self;
    self.titleField.toolTip = @"Menu item title (string or localized dict’s en value)";

    self.tooltipField = [self textFieldAt:NSMakeRect(0, 0, 380, 24)];
    self.tooltipLabel = [self label:@"Tooltip" at:NSMakeRect(0, 0, 80, 16)];
    [inspector addSubview:self.tooltipLabel];
    [inspector addSubview:self.tooltipField];
    self.tooltipField.delegate = self;
    self.tooltipField.placeholderString = @"hover help on the menu item";
    self.tooltipField.toolTip = @"Stored as settings.tooltip (also reads legacy title.tooltip)";

    self.iconSectionLabel = [self makeSectionLabel:@"Icon"];
    [inspector addSubview:self.iconSectionLabel];

    self.iconModePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 25)];
    self.iconModePopup.autoresizingMask = NSViewWidthSizable;
    self.iconModeLabel = [self label:@"Source" at:NSMakeRect(0, 0, 80, 16)];
    [inspector addSubview:self.iconModeLabel];
    [inspector addSubview:self.iconModePopup];
    [self.iconModePopup removeAllItems];
    [self.iconModePopup addItemsWithTitles:@[
        @"Automatic (type glyph / app icon)",
        @"No icon",
        @"CustomImage name",
        @"File or .app path",
    ]];
    self.iconModePopup.target = self;
    self.iconModePopup.action = @selector(iconModeChanged:);
    self.iconModePopup.toolTip = @"Automatic uses a built-in glyph (or the app icon for open.application). No icon shows title only. CustomImage name loads PNG from CustomImageForItem. File path uses any image or .app.";

    self.iconValueField = [self droppableTextFieldAt:NSMakeRect(0, 0, 346, 24)];
    self.iconValueLabel = [self label:@"Value" at:NSMakeRect(0, 0, 80, 16)];
    [inspector addSubview:self.iconValueLabel];
    [inspector addSubview:self.iconValueField];
    self.iconValueField.delegate = self;
    [self wireDropSupportForIconField];
    self.iconBrowseButton = [self attachBrowseButtonBesideField:self.iconValueField
                                                         inView:inspector
                                                         action:@selector(browseIconPath:)
                                                        toolTip:@"Choose an image or .app (or drop onto the field)"];
    self.iconRevealButton = [self attachRevealButtonAfterButton:self.iconBrowseButton
                                                         inView:inspector
                                                         action:@selector(revealIconPath:)];

    self.iconHintLabel = [self label:@"" at:NSMakeRect(kHITConfigInspectorControlX, 0, 380, 16)];
    self.iconHintLabel.alignment = NSTextAlignmentLeft;
    self.iconHintLabel.font = [NSFont systemFontOfSize:11];
    self.iconHintLabel.textColor = [NSColor tertiaryLabelColor];
    self.iconHintLabel.autoresizingMask = NSViewWidthSizable;
    [inspector addSubview:self.iconHintLabel];

    self.inspectorView = inspector;

    // Action / Behavior are reflowed when type changes (hidden rows must not leave gaps).
    self.actionSectionLabel = [self makeSectionLabel:@"Action"];
    [inspector addSubview:self.actionSectionLabel];

    self.keyField = [self droppableTextFieldAt:NSMakeRect(0, 0, 346, 24)];
    self.keyLabel = [self label:@"Script" at:NSMakeRect(0, 0, 80, 16)];
    [inspector addSubview:self.keyLabel];
    [inspector addSubview:self.keyField];
    self.keyField.delegate = self;
    [self wireDropSupportForKeyField];
    self.keyBrowseButton = [self attachBrowseButtonBesideField:self.keyField
                                                        inView:inspector
                                                        action:@selector(browseKeyPath:)
                                                       toolTip:@"Choose a file / app / script (or drop onto the field)"];
    self.keyRevealButton = [self attachRevealButtonAfterButton:self.keyBrowseButton
                                                        inView:inspector
                                                        action:@selector(revealKeyPath:)];

    self.fileField = [self droppableTextFieldAt:NSMakeRect(0, 0, 346, 24)];
    self.fileLabel = [self label:@"File" at:NSMakeRect(0, 0, 80, 16)];
    [inspector addSubview:self.fileLabel];
    [inspector addSubview:self.fileField];
    self.fileField.delegate = self;
    [self wireDropSupportForFileField];
    self.fileField.placeholderString = @"/path/to/open with the app";
    self.fileField.toolTip = @"open.application: open this file with the app (e.g. a log in Console). Drop a file here.";
    self.fileBrowseButton = [self attachBrowseButtonBesideField:self.fileField
                                                         inView:inspector
                                                         action:@selector(browseFilePath:)
                                                        toolTip:@"Choose a file to open with the app (or drop onto the field)"];
    self.fileRevealButton = [self attachRevealButtonAfterButton:self.fileBrowseButton
                                                         inView:inspector
                                                         action:@selector(revealFilePath:)];

    self.optionsField = [self textFieldAt:NSMakeRect(0, 0, 380, 24)];
    self.optionsLabel = [self label:@"Options" at:NSMakeRect(0, 0, 80, 16)];
    [inspector addSubview:self.optionsLabel];
    [inspector addSubview:self.optionsField];
    self.optionsField.delegate = self;

    self.bodyField = [self textFieldAt:NSMakeRect(0, 0, 380, 24)];
    self.bodyLabel = [self label:@"Body" at:NSMakeRect(0, 0, 80, 16)];
    [inspector addSubview:self.bodyLabel];
    [inspector addSubview:self.bodyField];
    self.bodyField.delegate = self;

    self.infoKindPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 25)];
    self.infoKindPopup.autoresizingMask = NSViewWidthSizable;
    self.infoKindLabel = [self label:@"Info" at:NSMakeRect(0, 0, 80, 16)];
    [inspector addSubview:self.infoKindLabel];
    [inspector addSubview:self.infoKindPopup];
    [self rebuildInfoKindPopup];
    self.infoKindPopup.target = self;
    self.infoKindPopup.action = @selector(infoKindChanged:);
    self.infoKindPopup.toolTip = @"Built-in system value to show in the menu";

    self.infoOptionPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 25)];
    self.infoOptionPopup.autoresizingMask = NSViewWidthSizable;
    self.infoOptionLabel = [self label:@"Format" at:NSMakeRect(0, 0, 80, 16)];
    [inspector addSubview:self.infoOptionLabel];
    [inspector addSubview:self.infoOptionPopup];
    self.infoOptionPopup.target = self;
    self.infoOptionPopup.action = @selector(infoOptionChanged:);

    self.infoInterfacePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 25)];
    self.infoInterfacePopup.autoresizingMask = NSViewWidthSizable;
    self.infoInterfaceLabel = [self label:@"Interface" at:NSMakeRect(0, 0, 80, 16)];
    [inspector addSubview:self.infoInterfaceLabel];
    [inspector addSubview:self.infoInterfacePopup];
    self.infoInterfacePopup.target = self;
    self.infoInterfacePopup.action = @selector(infoOptionChanged:);
    self.infoInterfacePopup.toolTip = @"Network interface to read (Automatic = primary/active)";

    self.uptimeWarnField = [self textFieldAt:NSMakeRect(0, 0, 80, 24)];
    self.uptimeWarnLabel = [self label:@"Warn ≥" at:NSMakeRect(0, 0, 80, 16)];
    [inspector addSubview:self.uptimeWarnLabel];
    [inspector addSubview:self.uptimeWarnField];
    self.uptimeWarnField.delegate = self;
    self.uptimeWarnField.placeholderString = @"7";
    self.uptimeWarnField.toolTip = @"Warning threshold (days / % / GB / dB depending on Info kind)";

    self.uptimeErrorField = [self textFieldAt:NSMakeRect(0, 0, 80, 24)];
    self.uptimeErrorLabel = [self label:@"Error ≥" at:NSMakeRect(0, 0, 80, 16)];
    [inspector addSubview:self.uptimeErrorLabel];
    [inspector addSubview:self.uptimeErrorField];
    self.uptimeErrorField.delegate = self;
    self.uptimeErrorField.placeholderString = @"14";
    self.uptimeErrorField.toolTip = @"Error threshold (days / % / GB / dB depending on Info kind)";

    self.repeatField = [self textFieldAt:NSMakeRect(0, 0, 80, 24)];
    self.repeatLabel = [self label:@"Repeat" at:NSMakeRect(0, 0, 80, 16)];
    [inspector addSubview:self.repeatLabel];
    [inspector addSubview:self.repeatField];
    self.repeatField.delegate = self;
    self.repeatField.placeholderString = @"seconds";

    self.notificationsSectionLabel = [self makeSectionLabel:@"Alerts"];
    [inspector addSubview:self.notificationsSectionLabel];

    self.notifyHintLabel = [self label:@"Thresholds decide yellow/red. Switches send a banner (title = menu title); edit the message as needed."
                                    at:NSMakeRect(kHITConfigInspectorControlX, 0, 380, 16)];
    self.notifyHintLabel.alignment = NSTextAlignmentLeft;
    self.notifyHintLabel.font = [NSFont systemFontOfSize:11];
    self.notifyHintLabel.textColor = [NSColor tertiaryLabelColor];
    self.notifyHintLabel.autoresizingMask = NSViewWidthSizable;
    [inspector addSubview:self.notifyHintLabel];

    self.notifyOKSwitch = [self notificationSwitchWithTitle:@"OK"
                                                     toolTip:@"notificationWhenStateTurnOK — banner title is the menu item title"];
    self.notifyOKField = [self textFieldAt:NSMakeRect(0, 0, 380, 24)];
    [inspector addSubview:self.notifyOKSwitch];
    [inspector addSubview:self.notifyOKField];
    self.notifyOKField.delegate = self;
    self.notifyOKField.toolTip = self.notifyOKSwitch.toolTip;

    self.notifyWarningSwitch = [self notificationSwitchWithTitle:@"Warning"
                                                          toolTip:@"notificationWhenStateTurnWarning"];
    self.notifyWarningField = [self textFieldAt:NSMakeRect(0, 0, 380, 24)];
    [inspector addSubview:self.notifyWarningSwitch];
    [inspector addSubview:self.notifyWarningField];
    self.notifyWarningField.delegate = self;
    self.notifyWarningField.toolTip = self.notifyWarningSwitch.toolTip;

    self.notifyErrorSwitch = [self notificationSwitchWithTitle:@"Error"
                                                        toolTip:@"notificationWhenStateTurnError"];
    self.notifyErrorField = [self textFieldAt:NSMakeRect(0, 0, 380, 24)];
    [inspector addSubview:self.notifyErrorSwitch];
    [inspector addSubview:self.notifyErrorField];
    self.notifyErrorField.delegate = self;
    self.notifyErrorField.toolTip = self.notifyErrorSwitch.toolTip;

    self.notifyUnavailableSwitch = [self notificationSwitchWithTitle:@"Unavail."
                                                              toolTip:@"notificationWhenStateTurnUnavailable"];
    self.notifyUnavailableField = [self textFieldAt:NSMakeRect(0, 0, 380, 24)];
    [inspector addSubview:self.notifyUnavailableSwitch];
    [inspector addSubview:self.notifyUnavailableField];
    self.notifyUnavailableField.delegate = self;
    self.notifyUnavailableField.toolTip = self.notifyUnavailableSwitch.toolTip;

    self.notifyNoneSwitch = [self notificationSwitchWithTitle:@"Clear"
                                                       toolTip:@"notificationWhenStateTurnNone — when state returns to none/cleared"];
    self.notifyNoneField = [self textFieldAt:NSMakeRect(0, 0, 380, 24)];
    [inspector addSubview:self.notifyNoneSwitch];
    [inspector addSubview:self.notifyNoneField];
    self.notifyNoneField.delegate = self;
    self.notifyNoneField.toolTip = self.notifyNoneSwitch.toolTip;

    self.behaviorSectionLabel = [self makeSectionLabel:@"Behavior"];
    [inspector addSubview:self.behaviorSectionLabel];

    self.skipGlobalCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 22)];
    self.skipGlobalCheckbox.buttonType = NSButtonTypeSwitch;
    self.skipGlobalCheckbox.title = @"Skip for global state";
    self.skipGlobalCheckbox.target = self;
    self.skipGlobalCheckbox.action = @selector(flagsChanged:);
    self.skipGlobalCheckbox.toolTip = @"Do not include this item’s state in the status-bar icon";
    [inspector addSubview:self.skipGlobalCheckbox];

    self.optionalDisplayCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 280, 22)];
    self.optionalDisplayCheckbox.buttonType = NSButtonTypeSwitch;
    self.optionalDisplayCheckbox.title = @"Optional display (Option key)";
    self.optionalDisplayCheckbox.target = self;
    self.optionalDisplayCheckbox.action = @selector(flagsChanged:);
    self.optionalDisplayCheckbox.toolTip = @"Only show this item while the Option key is held";
    [inspector addSubview:self.optionalDisplayCheckbox];

    self.hideIfUnavailableCheckbox = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 320, 22)];
    self.hideIfUnavailableCheckbox.buttonType = NSButtonTypeSwitch;
    self.hideIfUnavailableCheckbox.title = @"Hide if app/file/URL unavailable";
    self.hideIfUnavailableCheckbox.target = self;
    self.hideIfUnavailableCheckbox.action = @selector(flagsChanged:);
    self.hideIfUnavailableCheckbox.toolTip = @"hideIfNotAvailable for open.application / open.resource";
    [inspector addSubview:self.hideIfUnavailableCheckbox];

    self.footerHintLabel = [self label:@"Apply & Reload to preview. Use Export for plist, mobileconfig, script, or all three."
                                    at:NSMakeRect(0, 0, 520, 28)];
    self.footerHintLabel.alignment = NSTextAlignmentLeft;
    self.footerHintLabel.textColor = [NSColor secondaryLabelColor];
    self.footerHintLabel.font = [NSFont systemFontOfSize:11];
    self.footerHintLabel.autoresizingMask = NSViewWidthSizable;
    [inspector addSubview:self.footerHintLabel];

    // Start with Automatic icon UI + no type-specific Action rows until a selection loads.
    self.iconValueField.hidden = YES;
    self.iconValueLabel.hidden = YES;
    self.iconBrowseButton.hidden = YES;
    self.iconRevealButton.hidden = YES;
    self.keyField.hidden = YES;
    self.keyLabel.hidden = YES;
    self.keyBrowseButton.hidden = YES;
    self.keyRevealButton.hidden = YES;
    self.fileField.hidden = YES;
    self.fileLabel.hidden = YES;
    self.fileBrowseButton.hidden = YES;
    self.fileRevealButton.hidden = YES;
    self.optionsField.hidden = YES;
    self.optionsLabel.hidden = YES;
    self.bodyField.hidden = YES;
    self.bodyLabel.hidden = YES;
    self.infoKindPopup.hidden = YES;
    self.infoKindLabel.hidden = YES;
    self.infoOptionPopup.hidden = YES;
    self.infoOptionLabel.hidden = YES;
    self.infoInterfacePopup.hidden = YES;
    self.infoInterfaceLabel.hidden = YES;
    self.uptimeWarnField.hidden = YES;
    self.uptimeWarnLabel.hidden = YES;
    self.uptimeErrorField.hidden = YES;
    self.uptimeErrorLabel.hidden = YES;
    self.repeatField.hidden = YES;
    self.repeatLabel.hidden = YES;
    self.notificationsSectionLabel.hidden = YES;
    self.notifyHintLabel.hidden = YES;
    self.notifyOKField.hidden = YES;
    self.notifyOKSwitch.hidden = YES;
    self.notifyWarningField.hidden = YES;
    self.notifyWarningSwitch.hidden = YES;
    self.notifyErrorField.hidden = YES;
    self.notifyErrorSwitch.hidden = YES;
    self.notifyUnavailableField.hidden = YES;
    self.notifyUnavailableSwitch.hidden = YES;
    self.notifyNoneField.hidden = YES;
    self.notifyNoneSwitch.hidden = YES;
    self.hideIfUnavailableCheckbox.hidden = YES;
    self.iconHintLabel.stringValue = @"Uses a built-in type glyph in the menu (same as the left list).";

    [self reflowInspectorFromIconSection];

    inspectorScroll.documentView = inspector;
    [right addSubview:inspectorScroll];

    NSButton *applyButton = [self buttonWithTitle:@"Apply & Reload" action:@selector(apply:) frame:NSMakeRect(16, 16, 130, 32)];
    applyButton.keyEquivalent = @"\r";
    applyButton.toolTip = @"Write local preferences and rebuild the menu bar";

    NSPopUpButton *exportMenu = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(156, 16, 118, 32) pullsDown:YES];
    exportMenu.bezelStyle = NSBezelStyleRounded;
    exportMenu.toolTip = @"Export plist, mobileconfig, bash script, or all three into a folder";
    [exportMenu removeAllItems];
    [exportMenu addItemWithTitle:@"Export"];
    NSMenuItem *exportPlistItem = [[NSMenuItem alloc] initWithTitle:@"Plist…"
                                                             action:@selector(exportPlist:)
                                                      keyEquivalent:@""];
    exportPlistItem.target = self;
    exportPlistItem.toolTip = @"Export preference root as a plist";
    [[exportMenu menu] addItem:exportPlistItem];
    NSMenuItem *exportProfileItem = [[NSMenuItem alloc] initWithTitle:@"Mobileconfig…"
                                                               action:@selector(exportMobileconfig:)
                                                        keyEquivalent:@""];
    exportProfileItem.target = self;
    exportProfileItem.toolTip = @"Export an MDM configuration profile";
    [[exportMenu menu] addItem:exportProfileItem];
    NSMenuItem *exportScriptItem = [[NSMenuItem alloc] initWithTitle:@"Script…"
                                                              action:@selector(exportBashScript:)
                                                       keyEquivalent:@""];
    exportScriptItem.target = self;
    exportScriptItem.toolTip = @"Export a bash script that defaults-imports this configuration";
    [[exportMenu menu] addItem:exportScriptItem];
    [[exportMenu menu] addItem:[NSMenuItem separatorItem]];
    NSMenuItem *exportAllItem = [[NSMenuItem alloc] initWithTitle:@"All three…"
                                                           action:@selector(exportAll:)
                                                    keyEquivalent:@""];
    exportAllItem.target = self;
    exportAllItem.toolTip = @"Name a base file and write plist, mobileconfig, and script together";
    [[exportMenu menu] addItem:exportAllItem];

    NSButton *importButton = [self buttonWithTitle:@"Import…" action:@selector(importFile:) frame:NSMakeRect(284, 16, 90, 32)];
    importButton.toolTip = @"Import from plist or mobileconfig";
    importButton.autoresizingMask = NSViewMaxXMargin;
    [right addSubview:applyButton];
    [right addSubview:exportMenu];
    [right addSubview:importButton];

    [split addSubview:left];
    [split addSubview:right];
    [split setHoldingPriority:NSLayoutPriorityDefaultHigh + 10 forSubviewAtIndex:0];
    [split setHoldingPriority:NSLayoutPriorityDefaultLow forSubviewAtIndex:1];
    [split setPosition:kHITConfigLeftPaneWidth ofDividerAtIndex:0];
}

- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)action frame:(NSRect)frame {
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.bezelStyle = NSBezelStyleRounded;
    button.title = title;
    button.target = self;
    button.action = action;
    return button;
}

- (NSButton *)attachBrowseButtonBesideField:(NSTextField *)field
                                     inView:(NSView *)view
                                     action:(SEL)action
                                    toolTip:(NSString *)toolTip {
    NSButton *button = [self buttonWithTitle:@"…"
                                      action:action
                                       frame:NSMakeRect(NSMaxX(field.frame) + 6,
                                                        field.frame.origin.y,
                                                        28,
                                                        24)];
    button.toolTip = toolTip;
    [view addSubview:button];
    return button;
}

- (NSButton *)attachRevealButtonAfterButton:(NSButton *)browseButton
                                     inView:(NSView *)view
                                     action:(SEL)action {
    NSButton *button = [self buttonWithTitle:@"↩︎"
                                      action:action
                                       frame:NSMakeRect(NSMaxX(browseButton.frame) + 4,
                                                        browseButton.frame.origin.y,
                                                        28,
                                                        24)];
    if (@available(macOS 11.0, *)) {
        // folder alone reads as “open folder”; magnifying-glass badge = reveal/select in Finder.
        NSImage *reveal = [NSImage imageWithSystemSymbolName:@"folder.badge.magnifyingglass"
                                    accessibilityDescription:@"Reveal in Finder"];
        if (!reveal) {
            reveal = [NSImage imageWithSystemSymbolName:@"eye"
                               accessibilityDescription:@"Reveal in Finder"];
        }
        if (reveal) {
            button.image = reveal;
            button.imagePosition = NSImageOnly;
            button.title = @"";
        }
    }
    button.toolTip = @"Reveal in Finder";
    [view addSubview:button];
    return button;
}

- (NSString *)normalizedFilesystemPath:(NSString *)raw {
    NSString *path = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (path.length == 0) {
        return nil;
    }
    if ([path hasPrefix:@"file:"]) {
        NSURL *url = [NSURL URLWithString:path];
        path = url.path.length ? url.path : path;
    }
    path = [path stringByExpandingTildeInPath];
    return path.length ? path : nil;
}

- (BOOL)revealPathInFinder:(NSString *)rawPath {
    NSString *path = [self normalizedFilesystemPath:rawPath];
    if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSBeep();
        return NO;
    }
    [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:path]]];
    return YES;
}

- (NSString *)resolvedKeyFieldFilesystemPath {
    NSString *fid = [self selectedFunctionIdentifier];
    NSString *value = [self.keyField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (value.length == 0) {
        return nil;
    }
    if ([fid isEqualToString:@"public.script.item"]) {
        if ([value hasPrefix:@"/"] || [value hasPrefix:@"~"]) {
            return [self normalizedFilesystemPath:value];
        }
        NSString *scripts = @"/Library/Application Support/com.github.ygini.hello-it/CustomScripts";
        return [scripts stringByAppendingPathComponent:value];
    }
    if ([fid isEqualToString:@"public.command"]) {
        NSArray *parts = [self shellSplit:value];
        return parts.count ? [self normalizedFilesystemPath:parts.firstObject] : nil;
    }
    if ([fid isEqualToString:@"public.open.application"]) {
        if ([value hasSuffix:@".app"] || [value hasPrefix:@"/"]) {
            return [self normalizedFilesystemPath:value];
        }
        return [[NSWorkspace sharedWorkspace] fullPathForApplication:value];
    }
    if ([fid isEqualToString:@"public.open.resource"]) {
        return [self normalizedFilesystemPath:value];
    }
    return nil;
}

- (HITConfigIconMode)currentIconMode {
    return (HITConfigIconMode)self.iconModePopup.indexOfSelectedItem;
}

- (NSString *)resolvedIconFilesystemPathForReveal {
    HITConfigIconMode mode = [self currentIconMode];
    NSString *value = [self.iconValueField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (mode == HITConfigIconModeFilePath) {
        return [self normalizedFilesystemPath:value];
    }
    if (mode == HITConfigIconModeImageName && value.length > 0) {
        NSString *folder = @"/Library/Application Support/com.github.ygini.hello-it/CustomImageForItem";
        return [[folder stringByAppendingPathComponent:value] stringByAppendingPathExtension:@"png"];
    }
    return nil;
}

- (void)updateIconModeUI {
    HITConfigIconMode mode = [self currentIconMode];
    BOOL showValue = (mode == HITConfigIconModeImageName || mode == HITConfigIconModeFilePath);
    BOOL showBrowse = (mode == HITConfigIconModeFilePath);
    self.iconValueField.hidden = !showValue;
    self.iconValueLabel.hidden = !showValue;
    self.iconValueField.enabled = showValue;
    self.iconBrowseButton.hidden = !showBrowse;
    self.iconBrowseButton.enabled = showBrowse;
    self.iconRevealButton.hidden = !showValue;
    self.iconHintLabel.hidden = NO;

    if (mode == HITConfigIconModeAutomatic) {
        self.iconValueLabel.stringValue = @"Value";
        self.iconValueField.stringValue = @"";
        self.iconValueField.placeholderString = @"";
        NSString *fid = [self selectedFunctionIdentifier];
        BOOL isOpenApp = [fid isEqualToString:@"public.open.application"];
        self.iconHintLabel.stringValue = isOpenApp
            ? @"Uses the application’s icon when available, otherwise a generic glyph."
            : @"Uses a built-in type glyph in the menu (same as the left list).";
    } else if (mode == HITConfigIconModeNone) {
        self.iconValueLabel.stringValue = @"Value";
        self.iconValueField.stringValue = @"";
        self.iconValueField.placeholderString = @"";
        self.iconHintLabel.stringValue = @"Title only — no accessory icon in the menu.";
    } else if (mode == HITConfigIconModeImageName) {
        self.iconValueLabel.stringValue = @"Name";
        self.iconValueField.placeholderString = @"my-icon  (CustomImageForItem/my-icon.png)";
        self.iconHintLabel.stringValue = @"PNG in /Library/Application Support/…/CustomImageForItem/  (optional name-dark.png). Drop a PNG here.";
        self.iconValueField.toolTip = @"CustomImage basename. Drop a PNG (from CustomImageForItem preferred).";
    } else {
        self.iconValueLabel.stringValue = @"Path";
        self.iconValueField.placeholderString = @"/path/to/icon.png or /Applications/Foo.app";
        self.iconHintLabel.stringValue = @"Absolute path to an image file, or an .app (uses that app’s icon). Drop a file here.";
        self.iconValueField.toolTip = @"Image or .app path. Drop a file here, or use …";
    }
    [self updateRevealButtonsEnabled];
    if (!self.updatingUI) {
        [self reflowInspectorFromIconSection];
    }
}

- (void)iconModeChanged:(id)sender {
    if (self.updatingUI) {
        return;
    }
    [self updateIconModeUI];
    [self commitInspectorToSelectedItem];
}

- (void)updateRevealButtonsEnabled {
    NSString *iconPath = [self resolvedIconFilesystemPathForReveal];
    BOOL iconOK = iconPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:iconPath];
    self.iconRevealButton.enabled = !self.iconRevealButton.hidden && iconOK;

    NSString *keyPath = [self resolvedKeyFieldFilesystemPath];
    BOOL keyOK = keyPath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:keyPath];
    self.keyRevealButton.enabled = !self.keyRevealButton.hidden && keyOK;

    NSString *filePath = [self normalizedFilesystemPath:self.fileField.stringValue];
    BOOL fileOK = filePath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:filePath];
    self.fileRevealButton.enabled = !self.fileRevealButton.hidden && fileOK;
}

- (void)runOpenPanelForField:(NSTextField *)field
                       title:(NSString *)message
                allowedTypes:(NSArray<NSString *> *)types
               directoryHint:(NSString *)directoryHint
          canChooseDirectories:(BOOL)canChooseDirectories
       treatPackagesAsDirs:(BOOL)treatPackagesAsDirs
                  completion:(void (^)(NSString *path))completion {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = canChooseDirectories;
    panel.allowsMultipleSelection = NO;
    panel.treatsFilePackagesAsDirectories = treatPackagesAsDirs;
    if (types.count > 0) {
        panel.allowedFileTypes = types;
    }
    if (message.length > 0) {
        panel.message = message;
    }
    NSString *current = field.stringValue;
    if ([current hasPrefix:@"file://"]) {
        current = [[NSURL URLWithString:current] path] ?: current;
    }
    if (current.length > 0 && [current hasPrefix:@"/"]) {
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:current isDirectory:&isDir];
        panel.directoryURL = isDir ? [NSURL fileURLWithPath:current]
                                   : [[NSURL fileURLWithPath:current] URLByDeletingLastPathComponent];
    } else if (directoryHint.length > 0) {
        panel.directoryURL = [NSURL fileURLWithPath:directoryHint];
    }
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK || panel.URL.path.length == 0) {
            return;
        }
        if (completion) {
            completion(panel.URL.path);
        }
    }];
}

- (NSTextField *)textFieldAt:(NSRect)frame {
    NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
    field.autoresizingMask = NSViewWidthSizable;
    return field;
}

- (HITConfigDroppableTextField *)droppableTextFieldAt:(NSRect)frame {
    HITConfigDroppableTextField *field = [[HITConfigDroppableTextField alloc] initWithFrame:frame];
    field.autoresizingMask = NSViewWidthSizable;
    return field;
}

- (HITConfigDroppableTextField *)droppableField:(NSTextField *)field {
    return [field isKindOfClass:[HITConfigDroppableTextField class]] ? (HITConfigDroppableTextField *)field : nil;
}

- (void)wireDropSupportForIconField {
    HITConfigDroppableTextField *field = [self droppableField:self.iconValueField];
    if (!field) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    field.canAcceptDropPath = ^BOOL(NSString *path) {
        return [weakSelf canAcceptIconDropPath:path];
    };
    field.didDropPath = ^(NSString *path) {
        [weakSelf applyIconPathFromBrowseOrDrop:path];
    };
    field.toolTip = @"Image/.app path or CustomImage name — drop a file here, or use …";
}

- (void)wireDropSupportForKeyField {
    HITConfigDroppableTextField *field = [self droppableField:self.keyField];
    if (!field) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    field.canAcceptDropPath = ^BOOL(NSString *path) {
        return [weakSelf canAcceptKeyDropPath:path];
    };
    field.didDropPath = ^(NSString *path) {
        [weakSelf applyKeyPathFromBrowseOrDrop:path];
    };
}

- (void)wireDropSupportForFileField {
    HITConfigDroppableTextField *field = [self droppableField:self.fileField];
    if (!field) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    field.canAcceptDropPath = ^BOOL(NSString *path) {
        return [weakSelf canAcceptFileDropPath:path];
    };
    field.didDropPath = ^(NSString *path) {
        [weakSelf applyFilePathFromBrowseOrDrop:path];
    };
}

- (BOOL)canAcceptIconDropPath:(NSString *)path {
    if (!self.selectedItem || self.iconValueField.hidden || !self.iconValueField.isEnabled) {
        return NO;
    }
    HITConfigIconMode mode = [self currentIconMode];
    if (mode != HITConfigIconModeImageName && mode != HITConfigIconModeFilePath) {
        return NO;
    }
    if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return NO;
    }
    NSString *ext = path.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"app"]) {
        return YES;
    }
    static NSSet *imageExts;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        imageExts = [NSSet setWithArray:@[@"png", @"tiff", @"tif", @"icns", @"jpg", @"jpeg", @"gif"]];
    });
    if ([imageExts containsObject:ext]) {
        return YES;
    }
    return ([[NSImage alloc] initWithContentsOfFile:path] != nil);
}

- (BOOL)canAcceptKeyDropPath:(NSString *)path {
    if (!self.selectedItem || self.keyBrowseButton.hidden || self.keyField.hidden || !self.keyField.isEnabled) {
        return NO;
    }
    if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        return NO;
    }
    NSString *fid = [self selectedFunctionIdentifier];
    if ([fid isEqualToString:@"public.open.application"]) {
        return [path.pathExtension.lowercaseString isEqualToString:@"app"];
    }
    return YES;
}

- (BOOL)canAcceptFileDropPath:(NSString *)path {
    if (!self.selectedItem || self.fileBrowseButton.hidden || self.fileField.hidden || !self.fileField.isEnabled) {
        return NO;
    }
    return path.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:path];
}

- (void)applyIconPathFromBrowseOrDrop:(NSString *)path {
    if (path.length == 0) {
        return;
    }
    NSString *folder = @"/Library/Application Support/com.github.ygini.hello-it/CustomImageForItem";
    if ([path hasPrefix:folder] && [path.pathExtension.lowercaseString isEqualToString:@"png"]) {
        [self.iconModePopup selectItemAtIndex:HITConfigIconModeImageName];
        self.iconValueField.stringValue = path.stringByDeletingPathExtension.lastPathComponent;
        [self updateIconModeUI];
    } else {
        [self.iconModePopup selectItemAtIndex:HITConfigIconModeFilePath];
        self.iconValueField.stringValue = path;
        [self updateIconModeUI];
    }
    [self commitInspectorToSelectedItem];
    [self updateRevealButtonsEnabled];
}

- (void)applyFilePathFromBrowseOrDrop:(NSString *)path {
    if (path.length == 0 || self.fileField.hidden) {
        return;
    }
    self.fileField.stringValue = path;
    [self commitInspectorToSelectedItem];
    [self updateRevealButtonsEnabled];
}

- (void)applyKeyPathFromBrowseOrDrop:(NSString *)path {
    if (path.length == 0 || self.keyBrowseButton.hidden) {
        return;
    }
    NSString *fid = [self selectedFunctionIdentifier];
    if ([fid isEqualToString:@"public.script.item"]) {
        NSString *scripts = @"/Library/Application Support/com.github.ygini.hello-it/CustomScripts";
        if ([path hasPrefix:scripts]) {
            self.keyField.stringValue = path.lastPathComponent;
        } else {
            self.keyField.stringValue = path;
        }
    } else if ([fid isEqualToString:@"public.open.application"]) {
        NSString *name = [[NSFileManager defaultManager] displayNameAtPath:path];
        if ([name.lowercaseString hasSuffix:@".app"]) {
            name = name.stringByDeletingPathExtension;
        }
        self.keyField.stringValue = name.length ? name : path.lastPathComponent.stringByDeletingPathExtension;
        if ([self currentIconMode] == HITConfigIconModeAutomatic) {
            self.iconValueField.stringValue = @"";
        }
    } else if ([fid isEqualToString:@"public.open.resource"]) {
        self.keyField.stringValue = [[NSURL fileURLWithPath:path] absoluteString];
    } else {
        return;
    }
    [self commitInspectorToSelectedItem];
    [self updateRevealButtonsEnabled];
}

- (NSTextField *)label:(NSString *)text at:(NSRect)frame {
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.stringValue = text;
    label.bezeled = NO;
    label.drawsBackground = NO;
    label.editable = NO;
    label.selectable = NO;
    label.alignment = NSTextAlignmentRight;
    label.font = [NSFont systemFontOfSize:13];
    label.textColor = [NSColor secondaryLabelColor];
    return label;
}

- (NSTextField *)makeSectionLabel:(NSString *)title {
    NSTextField *header = [self label:title at:NSMakeRect(0, 0, 460, 18)];
    header.alignment = NSTextAlignmentLeft;
    header.font = [NSFont boldSystemFontOfSize:11];
    header.textColor = [NSColor secondaryLabelColor];
    header.autoresizingMask = NSViewWidthSizable;
    return header;
}

- (CGFloat)inspectorContentWidth {
    CGFloat width = self.inspectorScrollView.contentView.bounds.size.width;
    if (width < 200) {
        width = self.inspectorView.bounds.size.width;
    }
    if (width < 200) {
        width = NSWidth(self.window.contentLayoutRect) - kHITConfigLeftPaneWidth - 8;
    }
    return MAX(width, 420);
}

- (CGFloat)stretchyFieldWidthWithBrowseButtons:(NSInteger)buttonCount {
    CGFloat buttons = 0;
    if (buttonCount > 0) {
        buttons = 6 + buttonCount * kHITConfigInspectorButtonSize + MAX(0, buttonCount - 1) * kHITConfigInspectorButtonGap;
    }
    return MAX(160, [self inspectorContentWidth] - kHITConfigInspectorControlX - kHITConfigInspectorRightPad - buttons);
}

- (CGFloat)placeLabeledControl:(NSView *)control
                         label:(NSTextField *)label
                         atY:(CGFloat)y
                       width:(CGFloat)width
                      height:(CGFloat)height {
    const CGFloat labelHeight = 16;
    control.frame = NSMakeRect(kHITConfigInspectorControlX, y, width, height);
    label.frame = NSMakeRect(16, y + floor((height - labelHeight) / 2.0), kHITConfigInspectorLabelWidth, labelHeight);
    return y + height + 12;
}

- (void)placeBrowse:(NSButton *)browse reveal:(NSButton *)reveal besideField:(NSView *)field {
    CGFloat y = field.frame.origin.y;
    CGFloat h = field.frame.size.height;
    browse.frame = NSMakeRect(NSMaxX(field.frame) + 6, y, kHITConfigInspectorButtonSize, h);
    reveal.frame = NSMakeRect(NSMaxX(browse.frame) + kHITConfigInspectorButtonGap, y, kHITConfigInspectorButtonSize, h);
}

/// Full inspector layout (flipped, top → bottom). Fields stretch to the pane width.
- (void)reflowInspectorFromIconSection {
    if (!self.inspectorView) {
        return;
    }

    const CGFloat controlX = kHITConfigInspectorControlX;
    CGFloat fullWidth = [self stretchyFieldWidthWithBrowseButtons:0];
    CGFloat pathWidth = [self stretchyFieldWidthWithBrowseButtons:2];
    CGFloat y = 12;

    self.itemSectionLabel.frame = NSMakeRect(16, y, fullWidth + controlX - 16, 18);
    y += 26;

    y = [self placeLabeledControl:self.typePopup label:self.typeLabel atY:y width:MIN(fullWidth, 360) height:25];
    y = [self placeLabeledControl:self.titleField label:self.titleLabel atY:y width:fullWidth height:24];
    y = [self placeLabeledControl:self.tooltipField label:self.tooltipLabel atY:y width:fullWidth height:24];

    y += 8;
    BOOL showIcon = !self.iconModePopup.hidden;
    self.iconSectionLabel.hidden = !showIcon;
    if (showIcon) {
        self.iconSectionLabel.frame = NSMakeRect(16, y, fullWidth + controlX - 16, 18);
        y += 26;
        y = [self placeLabeledControl:self.iconModePopup label:self.iconModeLabel atY:y width:MIN(fullWidth, 360) height:25];

        if (!self.iconValueField.hidden) {
            NSInteger buttons = self.iconBrowseButton.hidden ? 1 : 2;
            CGFloat valueWidth = [self stretchyFieldWidthWithBrowseButtons:buttons];
            y = [self placeLabeledControl:self.iconValueField label:self.iconValueLabel atY:y width:valueWidth height:24];
            [self placeBrowse:self.iconBrowseButton reveal:self.iconRevealButton besideField:self.iconValueField];
        }

        if (!self.iconHintLabel.hidden && self.iconHintLabel.stringValue.length > 0) {
            self.iconHintLabel.frame = NSMakeRect(controlX, y, fullWidth, 16);
            y += 22;
        }
    }

    self.actionLayoutTopY = y;
    [self reflowInspectorFromActionSection];
}

/// Pack Action + Behavior tightly, skipping hidden rows (avoids gaps for command/title/etc.).
- (void)reflowInspectorFromActionSection {
    if (!self.inspectorView) {
        return;
    }
    const CGFloat controlX = kHITConfigInspectorControlX;
    CGFloat fullWidth = [self stretchyFieldWidthWithBrowseButtons:0];
    CGFloat pathWidth = [self stretchyFieldWidthWithBrowseButtons:2];
    CGFloat y = self.actionLayoutTopY;

    BOOL keyBrowseVisible = !self.keyBrowseButton.hidden && !self.keyField.hidden;
    BOOL fileBrowseVisible = !self.fileBrowseButton.hidden && !self.fileField.hidden;

    BOOL anyAction = !self.keyField.hidden || !self.fileField.hidden || !self.optionsField.hidden
        || !self.bodyField.hidden
        || !self.infoKindPopup.hidden || !self.infoOptionPopup.hidden || !self.infoInterfacePopup.hidden
        || !self.repeatField.hidden;
    self.actionSectionLabel.hidden = !anyAction;
    if (anyAction) {
        y += 8;
        self.actionSectionLabel.frame = NSMakeRect(16, y, fullWidth + controlX - 16, 18);
        y += 26;
    }

    if (!self.keyField.hidden) {
        self.keyLabel.hidden = NO;
        CGFloat width = keyBrowseVisible ? pathWidth : fullWidth;
        y = [self placeLabeledControl:self.keyField label:self.keyLabel atY:y width:width height:24];
        [self placeBrowse:self.keyBrowseButton reveal:self.keyRevealButton besideField:self.keyField];
        self.keyBrowseButton.hidden = !keyBrowseVisible;
        self.keyRevealButton.hidden = !keyBrowseVisible;
    } else {
        self.keyLabel.hidden = YES;
        self.keyBrowseButton.hidden = YES;
        self.keyRevealButton.hidden = YES;
    }

    if (!self.fileField.hidden) {
        self.fileLabel.hidden = NO;
        CGFloat fileWidth = fileBrowseVisible ? pathWidth : fullWidth;
        y = [self placeLabeledControl:self.fileField label:self.fileLabel atY:y width:fileWidth height:24];
        [self placeBrowse:self.fileBrowseButton reveal:self.fileRevealButton besideField:self.fileField];
        self.fileBrowseButton.hidden = !fileBrowseVisible;
        self.fileRevealButton.hidden = !fileBrowseVisible;
    } else {
        self.fileLabel.hidden = YES;
        self.fileBrowseButton.hidden = YES;
        self.fileRevealButton.hidden = YES;
    }

    if (!self.infoKindPopup.hidden) {
        self.infoKindLabel.hidden = NO;
        y = [self placeLabeledControl:self.infoKindPopup label:self.infoKindLabel atY:y width:MIN(fullWidth, 360) height:25];
    } else {
        self.infoKindLabel.hidden = YES;
    }

    if (!self.infoOptionPopup.hidden) {
        self.infoOptionLabel.hidden = NO;
        y = [self placeLabeledControl:self.infoOptionPopup label:self.infoOptionLabel atY:y width:MIN(fullWidth, 360) height:25];
    } else {
        self.infoOptionLabel.hidden = YES;
    }

    if (!self.infoInterfacePopup.hidden) {
        self.infoInterfaceLabel.hidden = NO;
        y = [self placeLabeledControl:self.infoInterfacePopup label:self.infoInterfaceLabel atY:y width:MIN(fullWidth, 360) height:25];
    } else {
        self.infoInterfaceLabel.hidden = YES;
    }

    if (!self.optionsField.hidden) {
        self.optionsLabel.hidden = NO;
        y = [self placeLabeledControl:self.optionsField label:self.optionsLabel atY:y width:fullWidth height:24];
    } else {
        self.optionsLabel.hidden = YES;
    }

    if (!self.bodyField.hidden) {
        self.bodyLabel.hidden = NO;
        y = [self placeLabeledControl:self.bodyField label:self.bodyLabel atY:y width:fullWidth height:24];
    } else {
        self.bodyLabel.hidden = YES;
    }

    if (!self.repeatField.hidden) {
        self.repeatLabel.hidden = NO;
        y = [self placeLabeledControl:self.repeatField label:self.repeatLabel atY:y width:100 height:24];
    } else {
        self.repeatLabel.hidden = YES;
    }

    // Capture before layout mutates hidden flags.
    BOOL showOK = !self.notifyOKField.hidden;
    BOOL showWarn = !self.notifyWarningField.hidden;
    BOOL showError = !self.notifyErrorField.hidden;
    BOOL showUnavail = !self.notifyUnavailableField.hidden;
    BOOL showNone = !self.notifyNoneField.hidden;
    BOOL showThresholds = !self.uptimeWarnField.hidden; // configureThresholdFields toggles both together
    BOOL showAlerts = showOK || showWarn || showError || showUnavail || showNone || showThresholds;
    self.notificationsSectionLabel.hidden = !showAlerts;
    self.notifyHintLabel.hidden = !showAlerts;
    if (showAlerts) {
        y += 8;
        self.notificationsSectionLabel.frame = NSMakeRect(16, y, fullWidth + controlX - 16, 18);
        y += 26;
        BOOL isCommandAlerts = [[self selectedFunctionIdentifier] isEqualToString:@"public.command"];
        self.notifyHintLabel.stringValue = isCommandAlerts
            ? @"Switch sends a banner when the command finishes (title = menu title)."
            : @"Thresholds decide yellow/red. Switches send a banner (title = menu title); edit the message as needed.";
        self.notifyHintLabel.frame = NSMakeRect(controlX, y, fullWidth, 16);
        y += 22;

        if (showOK) {
            y = [self placeAlertRowWithSwitch:self.notifyOKSwitch
                                       field:self.notifyOKField
                              thresholdLabel:nil
                              thresholdField:nil
                                         atY:y
                                       width:fullWidth];
        } else {
            self.notifyOKSwitch.hidden = YES;
            self.notifyOKField.hidden = YES;
        }

        if (showWarn || showThresholds) {
            y = [self placeAlertRowWithSwitch:showWarn ? self.notifyWarningSwitch : nil
                                       field:showWarn ? self.notifyWarningField : nil
                              thresholdLabel:showThresholds ? self.uptimeWarnLabel : nil
                              thresholdField:showThresholds ? self.uptimeWarnField : nil
                                         atY:y
                                       width:fullWidth];
            if (!showWarn) {
                self.notifyWarningSwitch.hidden = YES;
                self.notifyWarningField.hidden = YES;
            }
            if (!showThresholds) {
                self.uptimeWarnLabel.hidden = YES;
                self.uptimeWarnField.hidden = YES;
            }
        } else {
            self.notifyWarningSwitch.hidden = YES;
            self.notifyWarningField.hidden = YES;
            self.uptimeWarnLabel.hidden = YES;
            self.uptimeWarnField.hidden = YES;
        }

        if (showError || showThresholds) {
            y = [self placeAlertRowWithSwitch:showError ? self.notifyErrorSwitch : nil
                                       field:showError ? self.notifyErrorField : nil
                              thresholdLabel:showThresholds ? self.uptimeErrorLabel : nil
                              thresholdField:showThresholds ? self.uptimeErrorField : nil
                                         atY:y
                                       width:fullWidth];
            if (!showError) {
                self.notifyErrorSwitch.hidden = YES;
                self.notifyErrorField.hidden = YES;
            }
            if (!showThresholds) {
                self.uptimeErrorLabel.hidden = YES;
                self.uptimeErrorField.hidden = YES;
            }
        } else {
            self.notifyErrorSwitch.hidden = YES;
            self.notifyErrorField.hidden = YES;
            self.uptimeErrorLabel.hidden = YES;
            self.uptimeErrorField.hidden = YES;
        }

        if (showUnavail) {
            y = [self placeAlertRowWithSwitch:self.notifyUnavailableSwitch
                                       field:self.notifyUnavailableField
                              thresholdLabel:nil
                              thresholdField:nil
                                         atY:y
                                       width:fullWidth];
        } else {
            self.notifyUnavailableSwitch.hidden = YES;
            self.notifyUnavailableField.hidden = YES;
        }
        if (showNone) {
            y = [self placeAlertRowWithSwitch:self.notifyNoneSwitch
                                       field:self.notifyNoneField
                              thresholdLabel:nil
                              thresholdField:nil
                                         atY:y
                                       width:fullWidth];
        } else {
            self.notifyNoneSwitch.hidden = YES;
            self.notifyNoneField.hidden = YES;
        }
    } else {
        self.notifyOKSwitch.hidden = YES;
        self.notifyWarningSwitch.hidden = YES;
        self.notifyErrorSwitch.hidden = YES;
        self.notifyUnavailableSwitch.hidden = YES;
        self.notifyNoneSwitch.hidden = YES;
        self.uptimeWarnLabel.hidden = YES;
        self.uptimeErrorLabel.hidden = YES;
        self.uptimeWarnField.hidden = YES;
        self.uptimeErrorField.hidden = YES;
    }

    y += 8;
    self.behaviorSectionLabel.frame = NSMakeRect(16, y, fullWidth + controlX - 16, 18);
    y += 26;

    self.skipGlobalCheckbox.frame = NSMakeRect(controlX, y, MAX(280, fullWidth), 22);
    y += 28;
    self.optionalDisplayCheckbox.frame = NSMakeRect(controlX, y, MAX(280, fullWidth), 22);
    y += 28;
    if (!self.hideIfUnavailableCheckbox.hidden) {
        self.hideIfUnavailableCheckbox.frame = NSMakeRect(controlX, y, MAX(320, fullWidth), 22);
        y += 28;
    }
    y += 8;
    self.footerHintLabel.frame = NSMakeRect(16, y, fullWidth + controlX - 16, 28);
    y += 28;

    [self normalizeInspectorDocumentSizeWithContentMaxY:y];
    if (!self.suppressInspectorScrollToTop) {
        [self scrollInspectorToTop];
    }
}

- (void)normalizeInspectorDocumentSizeWithContentMaxY:(CGFloat)maxY {
    NSView *inspector = self.inspectorView;
    if (!inspector) {
        return;
    }
    CGFloat width = [self inspectorContentWidth];
    CGFloat height = MAX(maxY + 12, 40);
    inspector.frame = NSMakeRect(0, 0, width, height);
}

- (void)scrollInspectorToTop {
    NSClipView *clip = self.inspectorScrollView.contentView;
    if (!clip) {
        return;
    }
    [clip scrollToPoint:NSMakePoint(0, 0)];
    [self.inspectorScrollView reflectScrolledClipView:clip];
}

- (NSArray<NSDictionary *> *)knownFunctionEntries {
    // title = human label in Type menu; id = functionIdentifier written to prefs
    return @[
        @{@"id": @"public.submenu", @"title": @"Submenu"},
        @{@"id": @"public.title", @"title": @"Title"},
        @{@"id": @"public.separator", @"title": @"Separator"},
        @{@"id": @"public.system.info", @"title": @"System info"},
        @{@"id": @"public.munki", @"title": @"Munki"},
        @{@"id": @"public.script.item", @"title": @"Script"},
        @{@"id": @"public.command", @"title": @"Command"},
        @{@"id": @"public.open.application", @"title": @"Open application"},
        @{@"id": @"public.open.resource", @"title": @"Open URL / resource"},
        @{@"id": @"public.send.email", @"title": @"Send email"},
        @{@"id": @"public.test.http", @"title": @"HTTP test"},
        @{@"id": @"public.about", @"title": @"About"},
        @{@"id": @"public.quit", @"title": @"Quit"},
        @{@"id": @"public.ad.pass", @"title": @"AD password expiry"},
    ];
}

- (NSArray<NSString *> *)knownFunctionTitles {
    NSMutableArray *titles = [NSMutableArray array];
    for (NSDictionary *entry in [self knownFunctionEntries]) {
        [titles addObject:entry[@"title"]];
    }
    return titles;
}

- (NSArray<NSString *> *)knownFunctionIdentifiers {
    NSMutableArray *ids = [NSMutableArray array];
    for (NSDictionary *entry in [self knownFunctionEntries]) {
        [ids addObject:entry[@"id"]];
    }
    return ids;
}

- (void)rebuildTypePopup {
    [self.typePopup removeAllItems];
    for (NSDictionary *entry in [self knownFunctionEntries]) {
        [self.typePopup addItemWithTitle:entry[@"title"]];
        self.typePopup.lastItem.representedObject = entry[@"id"];
    }
}

- (NSString *)selectedFunctionIdentifier {
    id obj = self.typePopup.selectedItem.representedObject;
    if ([obj isKindOfClass:[NSString class]] && [obj length] > 0) {
        return obj;
    }
    // Fallback for dynamically-added unknown types (title may be the fid)
    return self.typePopup.titleOfSelectedItem ?: @"public.title";
}

- (void)selectFunctionIdentifier:(NSString *)fid {
    if (fid.length == 0) {
        fid = @"public.title";
    }
    for (NSMenuItem *item in self.typePopup.itemArray) {
        if ([item.representedObject isEqual:fid]) {
            [self.typePopup selectItem:item];
            return;
        }
    }
    [self.typePopup addItemWithTitle:fid];
    self.typePopup.lastItem.representedObject = fid;
    [self.typePopup selectItem:self.typePopup.lastItem];
}

- (void)rebuildInfoKindPopup {
    [self.infoKindPopup removeAllItems];
    NSArray *kinds = @[
        @{@"id": @"hostname", @"title": @"Hostname"},
        @{@"id": @"ip", @"title": @"IP address"},
        @{@"id": @"wifi", @"title": @"Wi‑Fi"},
        @{@"id": @"ethernet", @"title": @"Ethernet speed"},
        @{@"id": @"storage", @"title": @"Storage (free / purgeable)"},
        @{@"id": @"uptime", @"title": @"Uptime"},
        @{@"id": @"memory", @"title": @"Memory pressure"},
    ];
    for (NSDictionary *entry in kinds) {
        [self.infoKindPopup addItemWithTitle:entry[@"title"]];
        self.infoKindPopup.lastItem.representedObject = entry[@"id"];
    }
    self.infoKindLabel.stringValue = @"Info";
    self.infoKindPopup.toolTip = @"Built-in system value to show in the menu";
}

- (void)rebuildMunkiKindPopup {
    [self.infoKindPopup removeAllItems];
    NSArray *kinds = @[
        @{@"id": @"manifest", @"title": @"Manifest name"},
        @{@"id": @"pending", @"title": @"Pending update count"},
    ];
    for (NSDictionary *entry in kinds) {
        [self.infoKindPopup addItemWithTitle:entry[@"title"]];
        self.infoKindPopup.lastItem.representedObject = entry[@"id"];
    }
    self.infoKindLabel.stringValue = @"Option";
    self.infoKindPopup.toolTip = @"Munki value to show in the menu";
}

- (void)rebuildMailerPopup {
    [self.infoKindPopup removeAllItems];
    NSArray *kinds = @[
        @{@"id": @"default", @"title": @"Default mailer (mailto:)"},
        @{@"id": @"gmail", @"title": @"Gmail (browser compose)"},
    ];
    for (NSDictionary *entry in kinds) {
        [self.infoKindPopup addItemWithTitle:entry[@"title"]];
        self.infoKindPopup.lastItem.representedObject = entry[@"id"];
    }
    self.infoKindLabel.stringValue = @"Mailer";
    self.infoKindPopup.toolTip = @"default = system mail handler; gmail = Gmail compose in the browser";
}

- (NSString *)selectedInfoKind {
    id obj = self.infoKindPopup.selectedItem.representedObject;
    return [obj isKindOfClass:[NSString class]] ? obj : @"hostname";
}

- (void)selectInfoKind:(NSString *)kind {
    NSString *normalized = kind.lowercaseString.length ? kind.lowercaseString : @"hostname";
    for (NSMenuItem *item in self.infoKindPopup.itemArray) {
        if ([item.representedObject isEqual:normalized]) {
            [self.infoKindPopup selectItem:item];
            return;
        }
    }
    [self.infoKindPopup selectItemAtIndex:0];
}

- (void)rebuildInfoOptionPopupForKind:(NSString *)kind settings:(NSDictionary *)settings {
    [self.infoOptionPopup removeAllItems];
    kind = kind.lowercaseString;
    if ([kind isEqualToString:@"hostname"]) {
        self.infoOptionLabel.stringValue = @"Format";
        self.infoOptionPopup.toolTip = @"How the hostname is shown";
        NSArray *formats = @[
            @{@"id": @"%C", @"title": @"Computer Name"},
            @{@"id": @"%H", @"title": @"Host Name"},
            @{@"id": @"%L", @"title": @"Local Host Name"},
            @{@"id": @"%C (%H)", @"title": @"Computer Name (Host Name)"},
            @{@"id": @"%C — %L", @"title": @"Computer Name — Local"},
        ];
        for (NSDictionary *entry in formats) {
            [self.infoOptionPopup addItemWithTitle:entry[@"title"]];
            self.infoOptionPopup.lastItem.representedObject = entry[@"id"];
        }
        NSString *format = settings[@"format"] ?: @"%C";
        BOOL matched = NO;
        for (NSMenuItem *item in self.infoOptionPopup.itemArray) {
            if ([item.representedObject isEqual:format]) {
                [self.infoOptionPopup selectItem:item];
                matched = YES;
                break;
            }
        }
        if (!matched) {
            [self.infoOptionPopup addItemWithTitle:[NSString stringWithFormat:@"Custom (%@)", format]];
            self.infoOptionPopup.lastItem.representedObject = format;
            [self.infoOptionPopup selectItem:self.infoOptionPopup.lastItem];
        }
        self.infoOptionPopup.hidden = NO;
        self.infoOptionLabel.hidden = NO;
    } else if ([kind isEqualToString:@"ip"]) {
        self.infoOptionLabel.stringValue = @"If offline";
        self.infoOptionPopup.toolTip = @"What to do when no IP address is available";
        NSArray *modes = @[
            @{@"id": @0, @"title": @"Hide item"},
            @{@"id": @1, @"title": @"Show “No IP Address”"},
            @{@"id": @2, @"title": @"Show as error"},
        ];
        for (NSDictionary *entry in modes) {
            [self.infoOptionPopup addItemWithTitle:entry[@"title"]];
            self.infoOptionPopup.lastItem.representedObject = entry[@"id"];
        }
        NSInteger mode = [settings[@"mode"] integerValue];
        for (NSMenuItem *item in self.infoOptionPopup.itemArray) {
            if ([item.representedObject integerValue] == mode) {
                [self.infoOptionPopup selectItem:item];
                break;
            }
        }
        self.infoOptionPopup.hidden = NO;
        self.infoOptionLabel.hidden = NO;
    } else {
        self.infoOptionPopup.hidden = YES;
        self.infoOptionLabel.hidden = YES;
    }
}

- (void)rebuildInfoInterfacePopupWithSettings:(NSDictionary *)settings {
    [self.infoInterfacePopup removeAllItems];
    [self.infoInterfacePopup addItemWithTitle:@"Automatic"];
    self.infoInterfacePopup.lastItem.representedObject = @"";

    NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];
    struct ifaddrs *ifap = NULL;
    if (getifaddrs(&ifap) == 0) {
        for (struct ifaddrs *ifa = ifap; ifa != NULL; ifa = ifa->ifa_next) {
            if (!ifa->ifa_name) {
                continue;
            }
            if (ifa->ifa_flags & IFF_LOOPBACK) {
                continue;
            }
            NSString *name = [NSString stringWithUTF8String:ifa->ifa_name];
            if (name.length > 0) {
                [names addObject:name];
            }
        }
        freeifaddrs(ifap);
    }
    for (NSString *name in names) {
        [self.infoInterfacePopup addItemWithTitle:name];
        self.infoInterfacePopup.lastItem.representedObject = name;
    }

    NSString *selected = settings[@"interface"] ?: @"";
    BOOL matched = NO;
    for (NSMenuItem *item in self.infoInterfacePopup.itemArray) {
        NSString *value = item.representedObject ?: @"";
        if ([value isEqualToString:selected]) {
            [self.infoInterfacePopup selectItem:item];
            matched = YES;
            break;
        }
    }
    if (!matched && selected.length > 0) {
        [self.infoInterfacePopup addItemWithTitle:selected];
        self.infoInterfacePopup.lastItem.representedObject = selected;
        [self.infoInterfacePopup selectItem:self.infoInterfacePopup.lastItem];
    }
}

#pragma mark - Load / save model

- (void)loadFromDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *legacyContent = [defaults arrayForKey:kHITConfigContent];
    NSDictionary *settings = [defaults dictionaryForKey:kHITConfigSettings];
    NSArray *content = settings[kHITConfigContent] ?: legacyContent;

    if (![content isKindOfClass:[NSArray class]] || content.count == 0) {
        self.rootContent = [@[
            [@{
                kHITConfigFunctionIdentifier: @"public.title",
                kHITConfigSettings: [@{ kHITConfigTitle: @"Hello IT" } mutableCopy]
            } mutableCopy]
        ] mutableCopy];
        return;
    }

    self.rootContent = [self deepMutableCopyOfArray:content];
}

- (NSMutableArray *)deepMutableCopyOfArray:(NSArray *)array {
    // Must keep non-dictionary elements: programArguments / options are string arrays.
    // Previously only dictionaries were copied, so Command (and script options) came
    // back empty after loadFromDefaults / import.
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
    for (id obj in array) {
        if ([obj isKindOfClass:[NSDictionary class]]) {
            [result addObject:[self deepMutableCopyOfDictionary:obj]];
        } else if ([obj isKindOfClass:[NSArray class]]) {
            [result addObject:[self deepMutableCopyOfArray:obj]];
        } else if (obj != nil && obj != [NSNull null]) {
            [result addObject:obj];
        }
    }
    return result;
}

- (NSMutableDictionary *)deepMutableCopyOfDictionary:(NSDictionary *)dict {
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:dict.count];
    [dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([obj isKindOfClass:[NSDictionary class]]) {
            result[key] = [self deepMutableCopyOfDictionary:obj];
        } else if ([obj isKindOfClass:[NSArray class]]) {
            result[key] = [self deepMutableCopyOfArray:obj];
        } else {
            result[key] = obj;
        }
    }];
    return result;
}

- (NSDictionary *)immutableConfigurationRoot {
    return @{
        kHITConfigFunctionIdentifier: @"public.submenu",
        kHITConfigSettings: @{
            kHITConfigContent: [self immutableCopyOfArray:self.rootContent]
        }
    };
}

- (NSArray *)immutableCopyOfArray:(NSArray *)array {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:array.count];
    for (id obj in array) {
        if ([obj isKindOfClass:[NSDictionary class]]) {
            [result addObject:[self immutableCopyOfDictionary:obj]];
        } else if ([obj isKindOfClass:[NSArray class]]) {
            [result addObject:[self immutableCopyOfArray:obj]];
        } else if (obj != nil) {
            [result addObject:obj];
        }
    }
    return [result copy];
}

- (NSDictionary *)immutableCopyOfDictionary:(NSDictionary *)dict {
    NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:dict.count];
    [dict enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
        if ([obj isKindOfClass:[NSDictionary class]]) {
            result[key] = [self immutableCopyOfDictionary:obj];
        } else if ([obj isKindOfClass:[NSArray class]]) {
            result[key] = [self immutableCopyOfArray:obj];
        } else {
            result[key] = obj;
        }
    }];
    return [result copy];
}

#pragma mark - Outline

- (NSArray *)childrenOfItem:(id)item {
    if (item == nil) {
        return self.rootContent;
    }
    NSDictionary *settings = [item objectForKey:kHITConfigSettings];
    NSArray *content = [settings objectForKey:kHITConfigContent];
    return [content isKindOfClass:[NSArray class]] ? content : nil;
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    return [[self childrenOfItem:item] count];
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return [self childrenOfItem:item][index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    NSString *fid = [item objectForKey:kHITConfigFunctionIdentifier];
    return [fid isEqualToString:@"public.submenu"];
}

- (CGFloat)outlineView:(NSOutlineView *)outlineView heightOfRowByItem:(id)item {
    if ([[item objectForKey:kHITConfigFunctionIdentifier] isEqualToString:@"public.separator"]) {
        return 10;
    }
    return 24;
}

- (NSTableRowView *)outlineView:(NSOutlineView *)outlineView rowViewForItem:(id)item {
    NSTableRowView *row = [[NSTableRowView alloc] init];
    row.emphasized = NO;
    return row;
}

- (void)outlineView:(NSOutlineView *)outlineView didAddRowView:(NSTableRowView *)rowView forRow:(NSInteger)row {
    id item = [outlineView itemAtRow:row];
    NSString *tip = [self tooltipStringForItem:item];
    [rowView removeAllToolTips];
    rowView.toolTip = tip;
    if (tip.length > 0) {
        // Full-row tip; owner callback re-resolves by row index when shown.
        [rowView addToolTipRect:rowView.bounds owner:self userData:(void *)(intptr_t)row];
    }
}

- (void)outlineView:(NSOutlineView *)outlineView didRemoveRowView:(NSTableRowView *)rowView forRow:(NSInteger)row {
    [rowView removeAllToolTips];
    rowView.toolTip = nil;
}

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data {
    NSInteger row = (NSInteger)(intptr_t)data;
    if (row < 0 || row >= self.outlineView.numberOfRows) {
        return nil;
    }
    return [self tooltipStringForItem:[self.outlineView itemAtRow:row]];
}

- (NSString *)tooltipStringForItem:(id)item {
    if (![item isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *fid = item[kHITConfigFunctionIdentifier] ?: @"";
    NSString *itemTip = [self resolvedTooltipFromSettings:item[kHITConfigSettings]];
    if (itemTip.length > 0 && fid.length > 0) {
        return [NSString stringWithFormat:@"%@\n%@", itemTip, fid];
    }
    if (itemTip.length > 0) {
        return itemTip;
    }
    return fid.length ? fid : nil;
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
    NSString *fid = item[kHITConfigFunctionIdentifier] ?: @"";
    BOOL isSeparator = [fid isEqualToString:@"public.separator"];

    if (isSeparator) {
        NSString *sepId = @"HITMenuSeparatorCell";
        NSTableCellView *cell = [outlineView makeViewWithIdentifier:sepId owner:self];
        if (!cell) {
            cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 300, 10)];
            cell.identifier = sepId;
            NSBox *line = [[NSBox alloc] initWithFrame:NSMakeRect(22, 4, 264, 1)];
            line.boxType = NSBoxSeparator;
            line.autoresizingMask = NSViewWidthSizable;
            line.identifier = @"sepLine";
            [cell addSubview:line];
        }
        return cell;
    }

    // New id so recycled mis-aligned cells from earlier builds are not reused.
    NSString *identifier = @"HITMenuItemCell.v3";
    NSTableCellView *cell = [outlineView makeViewWithIdentifier:identifier owner:self];
    if (!cell) {
        cell = [[NSTableCellView alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
        cell.identifier = identifier;

        NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        imageView.translatesAutoresizingMaskIntoConstraints = NO;
        imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        imageView.imageAlignment = NSImageAlignCenter;
        imageView.identifier = @"glyph";
        cell.imageView = imageView;
        [cell addSubview:imageView];

        NSTextField *text = [[NSTextField alloc] initWithFrame:NSZeroRect];
        text.translatesAutoresizingMaskIntoConstraints = NO;
        text.bezeled = NO;
        text.drawsBackground = NO;
        text.editable = NO;
        text.selectable = NO;
        text.lineBreakMode = NSLineBreakByTruncatingTail;
        text.font = [NSFont menuFontOfSize:13];
        cell.textField = text;
        [cell addSubview:text];

        NSTextField *accessory = [[NSTextField alloc] initWithFrame:NSZeroRect];
        accessory.translatesAutoresizingMaskIntoConstraints = NO;
        accessory.bezeled = NO;
        accessory.drawsBackground = NO;
        accessory.editable = NO;
        accessory.selectable = NO;
        accessory.alignment = NSTextAlignmentRight;
        accessory.font = [NSFont menuFontOfSize:12];
        accessory.textColor = [NSColor secondaryLabelColor];
        accessory.identifier = @"accessory";
        [cell addSubview:accessory];

        [NSLayoutConstraint activateConstraints:@[
            [imageView.leadingAnchor constraintEqualToAnchor:cell.leadingAnchor constant:2],
            [imageView.widthAnchor constraintEqualToConstant:12],
            [imageView.heightAnchor constraintEqualToConstant:12],
            // Align glyph to the text baseline (SF Symbols sit high if centerY-matched).
            [imageView.centerYAnchor constraintEqualToAnchor:text.firstBaselineAnchor constant:-4],

            [text.leadingAnchor constraintEqualToAnchor:imageView.trailingAnchor constant:6],
            [text.centerYAnchor constraintEqualToAnchor:cell.centerYAnchor],
            [text.trailingAnchor constraintEqualToAnchor:accessory.leadingAnchor constant:-4],

            [accessory.trailingAnchor constraintEqualToAnchor:cell.trailingAnchor constant:-4],
            [accessory.centerYAnchor constraintEqualToAnchor:text.centerYAnchor],
            [accessory.widthAnchor constraintGreaterThanOrEqualToConstant:14],
        ]];
    }

    NSTextField *accessory = nil;
    for (NSView *sub in cell.subviews) {
        if ([sub.identifier isEqualToString:@"accessory"]) {
            accessory = (NSTextField *)sub;
            break;
        }
    }

    BOOL isTitle = [fid isEqualToString:@"public.title"];
    BOOL isSubmenu = [fid isEqualToString:@"public.submenu"];
    BOOL optional = [item[kHITConfigSettings][@"optionalDisplay"] boolValue];

    NSDictionary *itemSettings = item[kHITConfigSettings];
    if ([itemSettings[@"noIcon"] boolValue]) {
        cell.imageView.image = nil;
        cell.imageView.contentTintColor = nil;
    } else {
        NSImage *customIcon = [self customMenuImageForSettings:itemSettings];
        if (!customIcon && [fid isEqualToString:@"public.open.application"]) {
            customIcon = [self applicationIconForSettings:itemSettings];
        }
        if (customIcon) {
            cell.imageView.image = customIcon;
            cell.imageView.contentTintColor = nil;
        } else {
            cell.imageView.image = [self symbolImageForFunctionIdentifier:fid];
            cell.imageView.contentTintColor = [NSColor secondaryLabelColor];
        }
    }

    cell.textField.stringValue = [self displayTitleForItem:item];
    cell.textField.font = [NSFont menuFontOfSize:13];

    if (isTitle) {
        cell.textField.textColor = [NSColor secondaryLabelColor];
    } else if (optional) {
        cell.textField.textColor = [NSColor tertiaryLabelColor];
    } else {
        cell.textField.textColor = [NSColor labelColor];
    }

    NSMutableString *acc = [NSMutableString string];
    if (optional) {
        [acc appendString:@"⌥"];
    }
    if (isSubmenu) {
        if (acc.length) {
            [acc appendString:@" "];
        }
        [acc appendString:@"›"];
    }
    accessory.stringValue = acc;

    NSString *tip = [self tooltipStringForItem:item];
    cell.toolTip = tip;
    cell.textField.toolTip = tip;
    cell.imageView.toolTip = tip;
    return cell;
}

- (NSImage *)symbolImageForFunctionIdentifier:(NSString *)fid {
    NSString *name = @"questionmark.circle";
    if ([fid isEqualToString:@"public.submenu"]) {
        name = @"folder";
    } else if ([fid isEqualToString:@"public.title"]) {
        name = @"text.alignleft";
    } else if ([fid isEqualToString:@"public.separator"]) {
        name = @"minus";
    } else if ([fid isEqualToString:@"public.script.item"]) {
        name = @"terminal";
    } else if ([fid isEqualToString:@"public.command"]) {
        name = @"chevron.left.forwardslash.chevron.right";
    } else if ([fid isEqualToString:@"public.open.application"]) {
        name = @"app";
    } else if ([fid isEqualToString:@"public.open.resource"]) {
        name = @"link";
    } else if ([fid isEqualToString:@"public.send.email"]) {
        name = @"envelope";
    } else if ([fid isEqualToString:@"public.test.http"]) {
        name = @"network";
    } else if ([fid isEqualToString:@"public.about"]) {
        name = @"info.circle";
    } else if ([fid isEqualToString:@"public.quit"]) {
        name = @"xmark.circle";
    } else if ([fid isEqualToString:@"public.ad.pass"]) {
        name = @"key";
    } else if ([fid isEqualToString:@"public.system.info"]) {
        name = @"info.circle";
    } else if ([fid isEqualToString:@"public.munki"]) {
        name = @"shippingbox";
    } else if ([fid hasPrefix:@"public.cachethq"]) {
        name = @"heart.text.square";
    }

    NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:[self shortType:fid]];
    if (!image) {
        image = [NSImage imageWithSystemSymbolName:@"circle" accessibilityDescription:fid];
    }
    if (@available(macOS 11.0, *)) {
        NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:11
                                                                                              weight:NSFontWeightRegular
                                                                                               scale:NSImageSymbolScaleSmall];
        image = [image imageWithSymbolConfiguration:config];
    }
    image.template = YES;
    return image;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    NSInteger row = self.outlineView.selectedRow;
    if (row < 0) {
        // Don't clear selectedItem on transient deselection (e.g. reloadData).
        return;
    }
    NSMutableDictionary *item = [self.outlineView itemAtRow:row];
    if (item == self.selectedItem) {
        return;
    }
    self.selectedItem = item;
    [self populateInspector];
}

- (void)reloadOutlinePreservingSelection {
    id item = self.selectedItem;
    NSArray *expanded = [self currentlyExpandedItems];
    [self.outlineView reloadData];
    for (id expandedItem in expanded) {
        [self.outlineView expandItem:expandedItem];
    }
    if (item) {
        NSInteger row = [self.outlineView rowForItem:item];
        if (row >= 0) {
            [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
            self.selectedItem = item;
        }
    }
}

#pragma mark - Outline drag & drop

- (NSMutableArray *)mutableChildArrayOfItem:(id)item {
    if (item == nil) {
        return self.rootContent;
    }
    NSMutableDictionary *settings = item[kHITConfigSettings];
    if (![settings isKindOfClass:[NSMutableDictionary class]]) {
        settings = [NSMutableDictionary dictionary];
        item[kHITConfigSettings] = settings;
    }
    NSMutableArray *content = settings[kHITConfigContent];
    if (![content isKindOfClass:[NSMutableArray class]]) {
        content = [NSMutableArray array];
        settings[kHITConfigContent] = content;
    }
    return content;
}

- (BOOL)item:(id)item isDescendantOfItem:(id)ancestor {
    if (!item || !ancestor) {
        return NO;
    }
    id parent = [self.outlineView parentForItem:item];
    while (parent) {
        if (parent == ancestor) {
            return YES;
        }
        parent = [self.outlineView parentForItem:parent];
    }
    return NO;
}

- (nullable id<NSPasteboardWriting>)outlineView:(NSOutlineView *)outlineView pasteboardWriterForItem:(id)item {
    if (![item isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSPasteboardItem *pbItem = [[NSPasteboardItem alloc] init];
    [pbItem setString:@"1" forType:kHITConfigOutlineDragType];
    return pbItem;
}

- (void)outlineView:(NSOutlineView *)outlineView
    draggingSession:(NSDraggingSession *)session
   willBeginAtPoint:(NSPoint)screenPoint
           forItems:(NSArray *)draggedItems {
    self.draggedOutlineItems = draggedItems;
}

- (void)outlineView:(NSOutlineView *)outlineView
    draggingSession:(NSDraggingSession *)session
       endedAtPoint:(NSPoint)screenPoint
          operation:(NSDragOperation)operation {
    self.draggedOutlineItems = nil;
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView
                  validateDrop:(id<NSDraggingInfo>)info
                  proposedItem:(id)item
            proposedChildIndex:(NSInteger)index {
    id dragged = self.draggedOutlineItems.firstObject;
    if (!dragged) {
        return NSDragOperationNone;
    }
    if (dragged == item || [self item:item isDescendantOfItem:dragged]) {
        return NSDragOperationNone;
    }

    if (index == NSOutlineViewDropOnItemIndex) {
        NSString *fid = [item isKindOfClass:[NSDictionary class]] ? item[kHITConfigFunctionIdentifier] : nil;
        if ([fid isEqualToString:@"public.submenu"]) {
            return NSDragOperationMove;
        }
        // Drop-on a leaf → place as the next sibling instead.
        id parent = [outlineView parentForItem:item];
        NSArray *siblings = [self childrenOfItem:parent] ?: @[];
        NSInteger siblingIndex = [siblings indexOfObjectIdenticalTo:item];
        if (siblingIndex == NSNotFound) {
            return NSDragOperationNone;
        }
        [outlineView setDropItem:parent dropChildIndex:siblingIndex + 1];
        return NSDragOperationMove;
    }
    return NSDragOperationMove;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView
         acceptDrop:(id<NSDraggingInfo>)info
               item:(id)item
         childIndex:(NSInteger)index {
    [self commitInspectorToSelectedItem];
    id dragged = self.draggedOutlineItems.firstObject;
    if (![dragged isKindOfClass:[NSMutableDictionary class]]) {
        return NO;
    }

    id oldParent = [outlineView parentForItem:dragged];
    NSMutableArray *oldArray = [self mutableChildArrayOfItem:oldParent];
    NSInteger oldIndex = [oldArray indexOfObjectIdenticalTo:dragged];
    if (oldIndex == NSNotFound) {
        return NO;
    }

    id newParent = item;
    NSInteger newIndex = index;
    if (index == NSOutlineViewDropOnItemIndex) {
        // Nest into submenu.
        if (![[item objectForKey:kHITConfigFunctionIdentifier] isEqualToString:@"public.submenu"]) {
            return NO;
        }
        newParent = item;
        newIndex = (NSInteger)[self mutableChildArrayOfItem:item].count;
    }

    NSMutableArray *newArray = [self mutableChildArrayOfItem:newParent];
    if (oldArray == newArray) {
        if (newIndex > oldIndex) {
            newIndex -= 1;
        }
        if (newIndex == oldIndex) {
            return NO;
        }
        id moved = oldArray[oldIndex];
        [oldArray removeObjectAtIndex:oldIndex];
        if (newIndex < 0) {
            newIndex = 0;
        }
        if (newIndex > (NSInteger)newArray.count) {
            newIndex = (NSInteger)newArray.count;
        }
        [newArray insertObject:moved atIndex:newIndex];
    } else {
        [oldArray removeObjectAtIndex:oldIndex];
        if (newIndex < 0 || newIndex > (NSInteger)newArray.count) {
            newIndex = (NSInteger)newArray.count;
        }
        [newArray insertObject:dragged atIndex:newIndex];
    }

    NSArray *expanded = [self currentlyExpandedItems];
    [outlineView reloadData];
    for (id expandItem in expanded) {
        [outlineView expandItem:expandItem];
    }
    if (newParent) {
        [outlineView expandItem:newParent];
    }
    NSInteger row = [outlineView rowForItem:dragged];
    if (row >= 0) {
        [outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    }
    self.draggedOutlineItems = nil;
    return YES;
}

- (NSArray *)currentlyExpandedItems {
    NSMutableArray *items = [NSMutableArray array];
    for (NSInteger row = 0; row < self.outlineView.numberOfRows; row++) {
        id item = [self.outlineView itemAtRow:row];
        if ([self.outlineView isItemExpanded:item]) {
            [items addObject:item];
        }
    }
    return items;
}

- (NSString *)displayTitleForItem:(NSDictionary *)item {
    NSString *fid = item[kHITConfigFunctionIdentifier] ?: @"?";
    if ([fid isEqualToString:@"public.separator"]) {
        return @"";
    }
    if ([fid isEqualToString:@"public.quit"]) {
        return @"Quit";
    }
    if ([fid isEqualToString:@"public.about"]) {
        NSDictionary *aboutSettings = item[kHITConfigSettings];
        NSString *aboutTitle = [self resolvedTitleFromValue:aboutSettings[kHITConfigTitle]];
        return aboutTitle.length > 0 ? aboutTitle : @"About Hello IT";
    }

    NSDictionary *settings = item[kHITConfigSettings];
    NSString *title = [self resolvedTitleFromValue:settings[kHITConfigTitle]];
    if (title.length > 0) {
        return title;
    }
    return [self fallbackLabelForItem:item];
}

/// Matches HITBasicPlugin localizedString: string or { en / locale : "…" } dict.
- (NSString *)resolvedTitleFromValue:(id)value {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value length] > 0 ? value : nil;
    }
    if (![value isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSDictionary *dict = value;
    for (NSString *localIdentifier in @[
         [[NSLocale currentLocale] localeIdentifier],
         [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode] ?: @"",
         @"en"
         ]) {
        if (localIdentifier.length == 0) {
            continue;
        }
        id selected = dict[localIdentifier];
        if ([selected isKindOfClass:[NSString class]] && [selected length] > 0) {
            return selected;
        }
    }
    // Last resort: first string value (skip keys like tooltip).
    for (NSString *key in @[@"en", @"fr", @"de", @"es", @"nl"]) {
        id selected = dict[key];
        if ([selected isKindOfClass:[NSString class]] && [selected length] > 0) {
            return selected;
        }
    }
    for (NSString *key in dict) {
        if ([key isEqualToString:@"tooltip"]) {
            continue;
        }
        id selected = dict[key];
        if ([selected isKindOfClass:[NSString class]] && [selected length] > 0) {
            return selected;
        }
    }
    return nil;
}

- (NSString *)resolvedTooltipFromSettings:(NSDictionary *)settings {
    if (![settings isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    id tip = settings[@"tooltip"];
    if ([tip isKindOfClass:[NSString class]] && [tip length] > 0) {
        return tip;
    }
    if ([tip isKindOfClass:[NSDictionary class]]) {
        return [self resolvedTitleFromValue:tip];
    }
    // Legacy: some profiles stuffed tooltip inside the title dict (e.g. DetectX).
    id title = settings[kHITConfigTitle];
    if ([title isKindOfClass:[NSDictionary class]]) {
        id nested = title[@"tooltip"];
        if ([nested isKindOfClass:[NSString class]] && [nested length] > 0) {
            return nested;
        }
    }
    return nil;
}

- (NSString *)fallbackLabelForItem:(NSDictionary *)item {
    NSString *fid = item[kHITConfigFunctionIdentifier] ?: @"";
    NSDictionary *settings = item[kHITConfigSettings] ?: @{};

    if ([fid isEqualToString:@"public.script.item"]) {
        NSString *script = settings[@"script"] ?: settings[@"path"] ?: @"script";
        return [self humanizedScriptName:script];
    }
    if ([fid isEqualToString:@"public.system.info"]) {
        NSString *kind = settings[@"kind"] ?: @"hostname";
        return [kind capitalizedString];
    }
    if ([fid isEqualToString:@"public.munki"]) {
        NSString *kind = [settings[@"kind"] lowercaseString] ?: @"manifest";
        if ([kind isEqualToString:@"pending"]
            || [kind isEqualToString:@"pendingupdates"]
            || [kind isEqualToString:@"updates"]) {
            return @"Pending update count";
        }
        return @"Manifest name";
    }
    if ([fid isEqualToString:@"public.open.resource"]) {
        NSString *urlString = settings[@"URL"] ?: @"URL";
        NSURL *url = [NSURL URLWithString:urlString];
        if (url.host.length > 0) {
            return url.host;
        }
        if ([urlString hasPrefix:@"file://"]) {
            return urlString.lastPathComponent.length ? urlString.lastPathComponent : urlString;
        }
        return urlString;
    }
    if ([fid isEqualToString:@"public.send.email"]) {
        NSString *mailto = settings[@"mailto"] ?: @"email";
        NSString *mailer = [settings[@"mailer"] lowercaseString];
        if ([mailer isEqualToString:@"gmail"]) {
            return [NSString stringWithFormat:@"%@ (Gmail)", mailto];
        }
        return mailto;
    }
    if ([fid isEqualToString:@"public.open.application"]) {
        NSString *app = settings[@"app"] ?: @"app";
        NSString *file = settings[@"file"];
        if ([file isKindOfClass:[NSString class]] && file.length > 0) {
            return [NSString stringWithFormat:@"%@ → %@", app, file.lastPathComponent];
        }
        return app;
    }
    if ([fid isEqualToString:@"public.test.http"]) {
        NSString *urlString = settings[@"URL"] ?: @"HTTP test";
        NSURL *url = [NSURL URLWithString:urlString];
        return url.host.length ? url.host : urlString;
    }
    if ([fid isEqualToString:@"public.command"]) {
        NSArray *args = settings[@"programArguments"];
        if ([args isKindOfClass:[NSArray class]] && args.count > 0) {
            return [args componentsJoinedByString:@" "];
        }
        return @"command";
    }
    if ([fid isEqualToString:@"public.submenu"]) {
        return @"Submenu";
    }
    return [self shortType:fid];
}

- (NSString *)humanizedScriptName:(NSString *)script {
    NSString *base = script.lastPathComponent.stringByDeletingPathExtension;
    // com.github.ygini.hello-it.hostname → hostname
    // com.github.wardsparadox.hello-it.computerdetails.storagespace → storagespace
    NSString *lower = base.lowercaseString;
    for (NSString *marker in @[@".hello-it.", @".hello_it."]) {
        NSRange range = [lower rangeOfString:marker];
        if (range.location != NSNotFound) {
            NSString *tail = [base substringFromIndex:range.location + range.length];
            if (tail.length > 0) {
                base = tail;
                break;
            }
        }
    }
    // computerdetails.storagespace → Storage space
    base = [base stringByReplacingOccurrencesOfString:@"." withString:@" "];
    base = [base stringByReplacingOccurrencesOfString:@"-" withString:@" "];
    base = [base stringByReplacingOccurrencesOfString:@"_" withString:@" "];
    if (base.length == 0) {
        return script;
    }
    return [base capitalizedString];
}

- (NSString *)shortType:(NSString *)fid {
    if ([fid hasPrefix:@"public."]) {
        return [fid substringFromIndex:7];
    }
    return fid;
}

#pragma mark - Inspector

- (void)populateInspector {
    self.updatingUI = YES;
    NSMutableDictionary *item = self.selectedItem;
    if (!item) {
        self.updatingUI = NO;
        return;
    }

    NSString *fid = item[kHITConfigFunctionIdentifier] ?: @"public.title";
    [self selectFunctionIdentifier:fid];

    NSMutableDictionary *settings = item[kHITConfigSettings];
    if (![settings isKindOfClass:[NSMutableDictionary class]]) {
        settings = [self deepMutableCopyOfDictionary:settings ?: @{}];
        item[kHITConfigSettings] = settings;
    }

    NSString *resolvedTitle = [self resolvedTitleFromValue:settings[kHITConfigTitle]];
    self.titleField.stringValue = resolvedTitle ?: @"";
    if ([fid isEqualToString:@"public.script.item"] && resolvedTitle.length == 0) {
        self.titleField.placeholderString = [NSString stringWithFormat:@"optional — menu shows “%@” from script",
                                             [self humanizedScriptName:settings[@"script"] ?: @"script"]];
    } else if (([fid isEqualToString:@"public.system.info"] || [fid isEqualToString:@"public.munki"])
               && resolvedTitle.length == 0) {
        self.titleField.placeholderString = @"optional — title is filled by the live value";
    } else if ([fid isEqualToString:@"public.about"] && resolvedTitle.length == 0) {
        self.titleField.placeholderString = @"optional — defaults to “About Hello IT”";
    } else if (resolvedTitle.length == 0) {
        self.titleField.placeholderString = @"display title";
    } else {
        self.titleField.placeholderString = @"";
    }

    self.tooltipField.stringValue = [self resolvedTooltipFromSettings:settings] ?: @"";

    NSString *imagePath = settings[@"imagePath"];
    NSString *imageBase = settings[@"imageBaseName"];
    HITConfigIconMode mode = HITConfigIconModeAutomatic;
    NSString *iconValue = @"";
    if ([settings[@"noIcon"] boolValue]) {
        mode = HITConfigIconModeNone;
    } else if ([imagePath isKindOfClass:[NSString class]] && imagePath.length > 0) {
        mode = HITConfigIconModeFilePath;
        iconValue = imagePath;
    } else if ([imageBase isKindOfClass:[NSString class]] && imageBase.length > 0) {
        mode = HITConfigIconModeImageName;
        iconValue = imageBase;
    }
    [self.iconModePopup selectItemAtIndex:mode];
    self.iconValueField.stringValue = iconValue;

    [self configureTypeSpecificFields:fid settings:settings];

    self.skipGlobalCheckbox.state = [settings[@"skipForGlobalState"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.optionalDisplayCheckbox.state = [settings[@"optionalDisplay"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.hideIfUnavailableCheckbox.state = [settings[@"hideIfNotAvailable"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;

    self.updatingUI = NO;
}

- (void)configureTypeSpecificFields:(NSString *)fid settings:(NSDictionary *)settings {
    BOOL isSeparatorOrQuit = [fid isEqualToString:@"public.separator"] || [fid isEqualToString:@"public.quit"];
    BOOL isAbout = [fid isEqualToString:@"public.about"];
    BOOL isTitleOnly = [fid isEqualToString:@"public.title"] || [fid isEqualToString:@"public.submenu"] || isAbout;
    BOOL isScript = [fid isEqualToString:@"public.script.item"];
    BOOL isSystemInfo = [fid isEqualToString:@"public.system.info"];
    BOOL isMunki = [fid isEqualToString:@"public.munki"];
    BOOL isCommand = [fid isEqualToString:@"public.command"];
    BOOL isOpenApp = [fid isEqualToString:@"public.open.application"];
    BOOL isOpenResource = [fid isEqualToString:@"public.open.resource"];
    BOOL isSendEmail = [fid isEqualToString:@"public.send.email"];
    BOOL isHTTP = [fid isEqualToString:@"public.test.http"];
    BOOL isADPass = [fid isEqualToString:@"public.ad.pass"];

    self.titleField.enabled = !isSeparatorOrQuit;
    self.tooltipField.enabled = !isSeparatorOrQuit;

    // Icon — all item types except separator/quit
    BOOL allowIcon = !isSeparatorOrQuit;
    self.iconModePopup.hidden = !allowIcon;
    self.iconModeLabel.hidden = !allowIcon;
    self.iconModePopup.enabled = allowIcon;
    self.iconHintLabel.hidden = !allowIcon;
    if (!allowIcon) {
        [self.iconModePopup selectItemAtIndex:HITConfigIconModeAutomatic];
        self.iconValueField.stringValue = @"";
        self.iconValueField.hidden = YES;
        self.iconValueLabel.hidden = YES;
        self.iconBrowseButton.hidden = YES;
        self.iconRevealButton.hidden = YES;
    } else {
        [self updateIconModeUI];
    }

    // Primary key field (hidden for system.info / munki — uses menus instead)
    self.keyField.hidden = isSeparatorOrQuit || isTitleOnly || isADPass || isSystemInfo || isMunki;
    self.keyLabel.hidden = self.keyField.hidden;
    self.keyField.enabled = !self.keyField.hidden;
    // Browse for single-path key fields (script/app/file URL). Command is an argv line — type it.
    BOOL keyBrowse = isScript || isOpenApp || isOpenResource;
    self.keyBrowseButton.hidden = self.keyField.hidden || !keyBrowse;
    self.keyBrowseButton.enabled = !self.keyBrowseButton.hidden;
    self.keyRevealButton.hidden = self.keyBrowseButton.hidden;
    if (isScript) {
        self.keyBrowseButton.toolTip = @"Choose a script (CustomScripts basename, or absolute path) — or drop onto the field";
    } else if (isOpenApp) {
        self.keyBrowseButton.toolTip = @"Choose an application (.app) — or drop onto the field";
    } else if (isOpenResource) {
        self.keyBrowseButton.toolTip = @"Choose a local file (fills file:// URL) — or drop onto the field";
    }

    if (isScript) {
        self.keyLabel.stringValue = @"Script";
        self.keyField.stringValue = settings[@"script"] ?: settings[@"path"] ?: @"";
        self.keyField.placeholderString = @"basename under CustomScripts";
        self.keyField.toolTip = @"Script filename in CustomScripts (or absolute path). Drop a script here.";
    } else if (isCommand) {
        self.keyLabel.stringValue = @"Command";
        NSArray *args = settings[@"programArguments"];
        self.keyField.stringValue = [args isKindOfClass:[NSArray class]] ? [args componentsJoinedByString:@" "] : @"";
        self.keyField.placeholderString = @"/usr/bin/touch /Users/Shared/flag";
        self.keyField.toolTip = @"Executable then args (absolute path preferred). Bare names like touch are resolved via PATH.";
    } else if (isOpenResource || isHTTP) {
        self.keyLabel.stringValue = @"URL";
        self.keyField.stringValue = settings[@"URL"] ?: @"";
        self.keyField.placeholderString = isHTTP ? @"https://… (test target)" : @"https://… or file://… or munki://…";
        self.keyField.toolTip = isHTTP
            ? @"URL to fetch for the HTTP test"
            : @"URL or file:// resource to open. Drop a local file/folder to fill file://…";
    } else if (isOpenApp) {
        self.keyLabel.stringValue = @"App";
        self.keyField.stringValue = settings[@"app"] ?: @"";
        self.keyField.placeholderString = @"Managed Software Center";
        self.keyField.toolTip = @"Application name as Launch Services knows it. Drop a .app here, or use …";
    } else if (isSendEmail) {
        self.keyLabel.stringValue = @"To";
        self.keyField.stringValue = settings[@"mailto"] ?: @"";
        self.keyField.placeholderString = @"helpdesk@example.com";
        self.keyField.toolTip = @"Destination address (settings.mailto)";
    } else {
        self.keyField.stringValue = @"";
        self.keyField.placeholderString = @"";
    }

    // System info / Munki / Send email menus
    if (isSystemInfo) {
        [self rebuildInfoKindPopup];
        NSString *kind = settings[@"kind"] ?: @"hostname";
        [self selectInfoKind:kind];
        self.infoKindPopup.hidden = NO;
        self.infoKindLabel.hidden = NO;
        [self rebuildInfoOptionPopupForKind:kind settings:settings];
        BOOL needsInterface = [kind.lowercaseString isEqualToString:@"ip"] || [kind.lowercaseString isEqualToString:@"ethernet"];
        self.infoInterfacePopup.hidden = !needsInterface;
        self.infoInterfaceLabel.hidden = !needsInterface;
        if (needsInterface) {
            [self rebuildInfoInterfacePopupWithSettings:settings];
        }
        [self configureThresholdFieldsForKind:kind settings:settings];
    } else if (isMunki) {
        [self rebuildMunkiKindPopup];
        NSString *kind = settings[@"kind"] ?: @"manifest";
        [self selectInfoKind:kind];
        self.infoKindPopup.hidden = NO;
        self.infoKindLabel.hidden = NO;
        self.infoOptionPopup.hidden = YES;
        self.infoOptionLabel.hidden = YES;
        self.infoInterfacePopup.hidden = YES;
        self.infoInterfaceLabel.hidden = YES;
        [self configureThresholdFieldsForKind:nil settings:nil];
    } else if (isSendEmail) {
        [self rebuildMailerPopup];
        NSString *mailer = settings[@"mailer"] ?: @"default";
        [self selectInfoKind:mailer];
        self.infoKindPopup.hidden = NO;
        self.infoKindLabel.hidden = NO;
        self.infoOptionPopup.hidden = YES;
        self.infoOptionLabel.hidden = YES;
        self.infoInterfacePopup.hidden = YES;
        self.infoInterfaceLabel.hidden = YES;
        [self configureThresholdFieldsForKind:nil settings:nil];
    } else {
        self.infoKindPopup.hidden = YES;
        self.infoKindLabel.hidden = YES;
        self.infoOptionPopup.hidden = YES;
        self.infoOptionLabel.hidden = YES;
        self.infoInterfacePopup.hidden = YES;
        self.infoInterfaceLabel.hidden = YES;
        [self configureThresholdFieldsForKind:nil settings:nil];
    }

    // File (open.application) or Device URL (send.email)
    if (isOpenApp) {
        self.fileField.hidden = NO;
        self.fileLabel.hidden = NO;
        self.fileField.enabled = YES;
        self.fileBrowseButton.hidden = NO;
        self.fileBrowseButton.enabled = YES;
        self.fileRevealButton.hidden = NO;
        self.fileLabel.stringValue = @"File";
        self.fileField.stringValue = settings[@"file"] ?: @"";
        self.fileField.placeholderString = @"/path/to/open with the app";
        self.fileField.toolTip = @"open.application: open this file with the app (e.g. a log in Console)";
    } else if (isSendEmail) {
        self.fileField.hidden = NO;
        self.fileLabel.hidden = NO;
        self.fileField.enabled = YES;
        self.fileBrowseButton.hidden = YES;
        self.fileBrowseButton.enabled = NO;
        self.fileRevealButton.hidden = YES;
        self.fileLabel.stringValue = @"Device URL";
        self.fileField.stringValue = settings[@"deviceURL"] ?: @"";
        self.fileField.placeholderString = @"https://report.example.com/?$SERIAL";
        self.fileField.toolTip = @"Template URL; placeholders $SERIAL $UUID $HOSTNAME (resolved at click)";
    } else if (isHTTP) {
        self.fileField.hidden = NO;
        self.fileLabel.hidden = NO;
        self.fileField.enabled = YES;
        self.fileBrowseButton.hidden = YES;
        self.fileBrowseButton.enabled = NO;
        self.fileRevealButton.hidden = YES;
        self.fileLabel.stringValue = @"Failover";
        NSString *failover = settings[@"failoverHost"];
        self.fileField.stringValue = [failover isKindOfClass:[NSString class]] ? failover : @"cloudflare.com";
        self.fileField.placeholderString = @"cloudflare.com";
        self.fileField.toolTip = @"If the primary URL fails to connect, ping this FQDN. Success → Warning (not OK). Empty disables failover. Default: cloudflare.com";
    } else {
        self.fileField.hidden = YES;
        self.fileLabel.hidden = YES;
        self.fileField.enabled = NO;
        self.fileBrowseButton.hidden = YES;
        self.fileBrowseButton.enabled = NO;
        self.fileRevealButton.hidden = YES;
        self.fileField.stringValue = @"";
    }

    [self updateRevealButtonsEnabled];

    // Options / Mode / Subject
    if (isScript) {
        self.optionsLabel.hidden = NO;
        self.optionsField.hidden = NO;
        self.optionsField.enabled = YES;
        self.optionsLabel.stringValue = @"Options";
        NSArray *options = settings[@"options"];
        self.optionsField.stringValue = [options isKindOfClass:[NSArray class]] ? [options componentsJoinedByString:@" "] : @"";
        self.optionsField.placeholderString = @"space-separated script options";
        self.optionsField.toolTip = @"Passed to the script as options";
    } else if (isHTTP) {
        self.optionsLabel.hidden = NO;
        self.optionsField.hidden = NO;
        self.optionsField.enabled = YES;
        self.optionsLabel.stringValue = @"Mode";
        self.optionsField.stringValue = settings[@"mode"] ?: @"";
        self.optionsField.placeholderString = @"md5 or string";
        self.optionsField.toolTip = @"test.http mode (md5 / string); originalString kept if already set";
    } else if (isSendEmail) {
        self.optionsLabel.hidden = NO;
        self.optionsField.hidden = NO;
        self.optionsField.enabled = YES;
        self.optionsLabel.stringValue = @"Subject";
        self.optionsField.stringValue = settings[@"subject"] ?: @"";
        self.optionsField.placeholderString = @"Help — $SERIAL";
        self.optionsField.toolTip = @"Optional subject template ($SERIAL $UUID $HOSTNAME $DEVICE_URL)";
    } else {
        self.optionsLabel.hidden = YES;
        self.optionsField.hidden = YES;
        self.optionsField.enabled = NO;
        self.optionsField.stringValue = @"";
    }

    if (isSendEmail) {
        self.bodyLabel.hidden = NO;
        self.bodyField.hidden = NO;
        self.bodyField.enabled = YES;
        self.bodyField.stringValue = settings[@"body"] ?: @"";
        self.bodyField.placeholderString = @"optional — device URL block is appended automatically";
        self.bodyField.toolTip = @"Optional body template ($SERIAL $UUID $HOSTNAME $DEVICE_URL). If empty (or without $DEVICE_URL), a protected block + device URL is appended.";
    } else {
        self.bodyLabel.hidden = YES;
        self.bodyField.hidden = YES;
        self.bodyField.enabled = NO;
        self.bodyField.stringValue = @"";
    }

    // Repeat
    BOOL showRepeat = isScript || isHTTP || isADPass || isSystemInfo || isMunki;
    self.repeatLabel.hidden = !showRepeat;
    self.repeatField.hidden = !showRepeat;
    self.repeatField.enabled = showRepeat;
    id repeat = settings[@"repeat"];
    self.repeatField.stringValue = (showRepeat && repeat) ? [NSString stringWithFormat:@"%@", repeat] : @"";

    // Alerts: state-change notifications, or Command completion banner
    BOOL showNotifications = [self functionSupportsNotifications:fid];
    [self configureNotificationControlsVisible:showNotifications settings:settings];

    self.hideIfUnavailableCheckbox.hidden = !(isOpenApp || isOpenResource);
    self.hideIfUnavailableCheckbox.enabled = isOpenApp || isOpenResource;

    [self reflowInspectorFromIconSection];
}

- (void)commitInspectorToSelectedItem {
    if (self.updatingUI || !self.selectedItem) {
        return;
    }

    NSMutableDictionary *item = self.selectedItem;
    NSString *fid = [self selectedFunctionIdentifier];
    NSString *previousFid = item[kHITConfigFunctionIdentifier];
    item[kHITConfigFunctionIdentifier] = fid;

    NSMutableDictionary *settings = item[kHITConfigSettings];
    if (![settings isKindOfClass:[NSMutableDictionary class]]) {
        settings = [NSMutableDictionary dictionary];
        item[kHITConfigSettings] = settings;
    }

    // Preserve submenu children when changing other fields
    NSArray *existingContent = [settings[kHITConfigContent] copy];
    // Preserve test.http originalString / related keys unless type changes away
    NSString *existingOriginalString = [settings[@"originalString"] copy];
    NSNumber *existingIgnoreSystemState = settings[@"ignoreSystemState"];

    [self writeTitle:self.titleField.stringValue intoSettings:settings];
    [self writeTooltip:self.tooltipField.stringValue intoSettings:settings];
    [self writeIconSettingsIntoSettings:settings];

    // Clear type-specific keys, then write only what this type uses (keeps unknown keys intact).
    [settings removeObjectForKey:@"script"];
    [settings removeObjectForKey:@"path"];
    [settings removeObjectForKey:@"URL"];
    [settings removeObjectForKey:@"app"];
    [settings removeObjectForKey:@"file"];
    [settings removeObjectForKey:@"appURL"];
    [settings removeObjectForKey:@"args"];
    [settings removeObjectForKey:@"programArguments"];
    [settings removeObjectForKey:@"options"];
    [settings removeObjectForKey:@"mode"];
    [settings removeObjectForKey:@"kind"];
    [settings removeObjectForKey:@"format"];
    [settings removeObjectForKey:@"interface"];
    [settings removeObjectForKey:@"warnDays"];
    [settings removeObjectForKey:@"errorDays"];
    [settings removeObjectForKey:@"warnPercent"];
    [settings removeObjectForKey:@"errorPercent"];
    [settings removeObjectForKey:@"warnBelowGB"];
    [settings removeObjectForKey:@"errorBelowGB"];
    [settings removeObjectForKey:@"warnBelowSNR"];
    [settings removeObjectForKey:@"errorBelowSNR"];
    [settings removeObjectForKey:@"mailto"];
    [settings removeObjectForKey:@"deviceURL"];
    [settings removeObjectForKey:@"failoverHost"];
    [settings removeObjectForKey:@"mailer"];
    [settings removeObjectForKey:@"subject"];
    [settings removeObjectForKey:@"body"];
    [settings removeObjectForKey:@"repeat"];
    [settings removeObjectForKey:@"hideIfNotAvailable"];
    [settings removeObjectForKey:@"notifyOnCompletion"];
    // Preserve localized notification dicts while rewriting (cleared below if type doesn't support them).
    id existingNotifyOK = [settings[@"notificationWhenStateTurnOK"] copy];
    id existingNotifyWarning = [settings[@"notificationWhenStateTurnWarning"] copy];
    id existingNotifyError = [settings[@"notificationWhenStateTurnError"] copy];
    id existingNotifyUnavailable = [settings[@"notificationWhenStateTurnUnavailable"] copy];
    id existingNotifyNone = [settings[@"notificationWhenStateTurnNone"] copy];
    id existingNotifyOnCompletion = [settings[@"notificationOnCompletion"] copy];
    [settings removeObjectForKey:@"notificationWhenStateTurnOK"];
    [settings removeObjectForKey:@"notificationWhenStateTurnWarning"];
    [settings removeObjectForKey:@"notificationWhenStateTurnError"];
    [settings removeObjectForKey:@"notificationWhenStateTurnUnavailable"];
    [settings removeObjectForKey:@"notificationWhenStateTurnNone"];
    [settings removeObjectForKey:@"notificationOnCompletion"];
    if (![fid isEqualToString:@"public.test.http"]) {
        [settings removeObjectForKey:@"originalString"];
        [settings removeObjectForKey:@"ignoreSystemState"];
        [settings removeObjectForKey:@"unmatchingResult"];
        [settings removeObjectForKey:@"failedConnection"];
    }

    NSString *keyValue = self.keyField.stringValue;
    if ([fid isEqualToString:@"public.script.item"]) {
        if (keyValue.length) {
            // Absolute path → settings.path; otherwise CustomScripts basename → settings.script
            if ([keyValue hasPrefix:@"/"] || [keyValue hasPrefix:@"~"]) {
                settings[@"path"] = keyValue;
            } else {
                settings[@"script"] = keyValue;
            }
        }
        if (self.optionsField.stringValue.length > 0) {
            settings[@"options"] = [self shellSplit:self.optionsField.stringValue];
        }
        if (self.repeatField.stringValue.length > 0) {
            settings[@"repeat"] = @([self.repeatField.stringValue integerValue]);
        }
    } else if ([fid isEqualToString:@"public.system.info"]) {
        NSString *kind = [self selectedInfoKind];
        settings[@"kind"] = kind;
        if ([kind isEqualToString:@"hostname"]) {
            id format = self.infoOptionPopup.selectedItem.representedObject;
            settings[@"format"] = [format isKindOfClass:[NSString class]] && [format length] > 0 ? format : @"%C";
        } else if ([kind isEqualToString:@"ip"]) {
            id mode = self.infoOptionPopup.selectedItem.representedObject;
            settings[@"mode"] = [mode isKindOfClass:[NSNumber class]] ? mode : @0;
            NSString *iface = self.infoInterfacePopup.selectedItem.representedObject;
            if ([iface isKindOfClass:[NSString class]] && iface.length > 0) {
                settings[@"interface"] = iface;
            }
        } else if ([kind isEqualToString:@"ethernet"]) {
            NSString *iface = self.infoInterfacePopup.selectedItem.representedObject;
            if ([iface isKindOfClass:[NSString class]] && iface.length > 0) {
                settings[@"interface"] = iface;
            }
        } else if ([kind isEqualToString:@"uptime"] || [kind isEqualToString:@"memory"]
                   || [kind isEqualToString:@"storage"] || [kind isEqualToString:@"wifi"]) {
            [self writeThresholdFieldsForKind:kind intoSettings:settings];
        }
        if (self.repeatField.stringValue.length > 0) {
            settings[@"repeat"] = @([self.repeatField.stringValue integerValue]);
        } else {
            settings[@"repeat"] = @60;
        }
    } else if ([fid isEqualToString:@"public.munki"]) {
        NSString *kind = [self selectedInfoKind];
        settings[@"kind"] = kind.length ? kind : @"manifest";
        if (self.repeatField.stringValue.length > 0) {
            settings[@"repeat"] = @([self.repeatField.stringValue integerValue]);
        } else {
            // Pending updates benefit from a longer interval; match the classic example default.
            settings[@"repeat"] = [settings[@"kind"] isEqualToString:@"pending"] ? @360 : @60;
        }
    } else if ([fid isEqualToString:@"public.command"]) {
        if (keyValue.length) {
            settings[@"programArguments"] = [self shellSplit:keyValue];
        }
    } else if ([fid isEqualToString:@"public.open.resource"]) {
        if (keyValue.length) {
            settings[@"URL"] = keyValue;
        }
        if (self.hideIfUnavailableCheckbox.state == NSControlStateValueOn) {
            settings[@"hideIfNotAvailable"] = @YES;
        }
    } else if ([fid isEqualToString:@"public.send.email"]) {
        if (keyValue.length) {
            settings[@"mailto"] = keyValue;
        }
        if (self.fileField.stringValue.length > 0) {
            settings[@"deviceURL"] = self.fileField.stringValue;
        }
        NSString *mailer = [self selectedInfoKind];
        settings[@"mailer"] = ([mailer isEqualToString:@"gmail"] ? @"gmail" : @"default");
        if (self.optionsField.stringValue.length > 0) {
            settings[@"subject"] = self.optionsField.stringValue;
        }
        if (self.bodyField.stringValue.length > 0) {
            settings[@"body"] = self.bodyField.stringValue;
        }
    } else if ([fid isEqualToString:@"public.open.application"]) {
        if (keyValue.length) {
            settings[@"app"] = keyValue;
        }
        if (self.fileField.stringValue.length > 0) {
            settings[@"file"] = self.fileField.stringValue;
        }
        if (self.hideIfUnavailableCheckbox.state == NSControlStateValueOn) {
            settings[@"hideIfNotAvailable"] = @YES;
        }
    } else if ([fid isEqualToString:@"public.test.http"]) {
        if (keyValue.length) {
            settings[@"URL"] = keyValue;
        }
        if (self.optionsField.stringValue.length > 0) {
            settings[@"mode"] = self.optionsField.stringValue;
        }
        NSString *failover = [self.fileField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // Always persist so runtime can distinguish “default” vs cleared; empty disables failover.
        settings[@"failoverHost"] = failover ?: @"";
        if (self.repeatField.stringValue.length > 0) {
            settings[@"repeat"] = @([self.repeatField.stringValue integerValue]);
        }
        if (existingOriginalString) {
            settings[@"originalString"] = existingOriginalString;
        }
        if (existingIgnoreSystemState) {
            settings[@"ignoreSystemState"] = existingIgnoreSystemState;
        } else if (!previousFid || [previousFid isEqualToString:@"public.test.http"]) {
            // keep prior behavior for Internet checks
        }
    } else if ([fid isEqualToString:@"public.ad.pass"]) {
        if (self.repeatField.stringValue.length > 0) {
            settings[@"repeat"] = @([self.repeatField.stringValue integerValue]);
        }
    }

    if ([self functionSupportsNotifications:fid]) {
        NSSet<NSString *> *applicable = [self applicableNotificationKeys];
        if ([applicable containsObject:@"notificationWhenStateTurnOK"]) {
            [self writeNotificationFromSwitch:self.notifyOKSwitch
                                        field:self.notifyOKField
                                          key:@"notificationWhenStateTurnOK"
                               defaultMessage:[self defaultNotificationMessageForKey:@"notificationWhenStateTurnOK"]
                                 intoSettings:settings
                                     existing:existingNotifyOK];
        }
        if ([applicable containsObject:@"notificationWhenStateTurnWarning"]) {
            [self writeNotificationFromSwitch:self.notifyWarningSwitch
                                        field:self.notifyWarningField
                                          key:@"notificationWhenStateTurnWarning"
                               defaultMessage:[self defaultNotificationMessageForKey:@"notificationWhenStateTurnWarning"]
                                 intoSettings:settings
                                     existing:existingNotifyWarning];
        }
        if ([applicable containsObject:@"notificationWhenStateTurnError"]) {
            [self writeNotificationFromSwitch:self.notifyErrorSwitch
                                        field:self.notifyErrorField
                                          key:@"notificationWhenStateTurnError"
                               defaultMessage:[self defaultNotificationMessageForKey:@"notificationWhenStateTurnError"]
                                 intoSettings:settings
                                     existing:existingNotifyError];
        }
        if ([applicable containsObject:@"notificationWhenStateTurnUnavailable"]) {
            [self writeNotificationFromSwitch:self.notifyUnavailableSwitch
                                        field:self.notifyUnavailableField
                                          key:@"notificationWhenStateTurnUnavailable"
                               defaultMessage:[self defaultNotificationMessageForKey:@"notificationWhenStateTurnUnavailable"]
                                 intoSettings:settings
                                     existing:existingNotifyUnavailable];
        }
        if ([applicable containsObject:@"notificationWhenStateTurnNone"]) {
            [self writeNotificationFromSwitch:self.notifyNoneSwitch
                                        field:self.notifyNoneField
                                          key:@"notificationWhenStateTurnNone"
                               defaultMessage:[self defaultNotificationMessageForKey:@"notificationWhenStateTurnNone"]
                                 intoSettings:settings
                                     existing:existingNotifyNone];
        }
        if ([applicable containsObject:@"notificationOnCompletion"]) {
            // Same Alerts row as state turns; bool keeps runtime enabled even if message is customized later.
            if (self.notifyOKSwitch.state == NSControlStateValueOn) {
                settings[@"notifyOnCompletion"] = @YES;
            }
            [self writeNotificationFromSwitch:self.notifyOKSwitch
                                        field:self.notifyOKField
                                          key:@"notificationOnCompletion"
                               defaultMessage:[self defaultNotificationMessageForKey:@"notificationOnCompletion"]
                                 intoSettings:settings
                                     existing:existingNotifyOnCompletion];
        }
    }

    if (self.skipGlobalCheckbox.state == NSControlStateValueOn) {
        settings[@"skipForGlobalState"] = @YES;
    } else {
        [settings removeObjectForKey:@"skipForGlobalState"];
    }

    if (self.optionalDisplayCheckbox.state == NSControlStateValueOn) {
        settings[@"optionalDisplay"] = @YES;
    } else {
        [settings removeObjectForKey:@"optionalDisplay"];
    }

    if ([fid isEqualToString:@"public.submenu"]) {
        if (existingContent) {
            settings[kHITConfigContent] = [existingContent mutableCopy];
        } else if (![settings[kHITConfigContent] isKindOfClass:[NSMutableArray class]]) {
            settings[kHITConfigContent] = [NSMutableArray array];
        }
    } else {
        [settings removeObjectForKey:kHITConfigContent];
    }

    NSInteger row = [self.outlineView rowForItem:item];
    if (row >= 0) {
        // Keep the same selection while refreshing the row label.
        NSIndexSet *selected = self.outlineView.selectedRowIndexes;
        [self.outlineView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row]
                                    columnIndexes:[NSIndexSet indexSetWithIndex:0]];
        if (selected.count > 0) {
            [self.outlineView selectRowIndexes:selected byExtendingSelection:NO];
        } else {
            [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        }
        self.selectedItem = item;
    }
}

- (BOOL)functionSupportsStateNotifications:(NSString *)fid {
    // HITAdvancedPlugin fires notificationWhenStateTurn* when testState changes.
    return [fid isEqualToString:@"public.script.item"]
        || [fid isEqualToString:@"public.test.http"]
        || [fid isEqualToString:@"public.system.info"]
        || [fid isEqualToString:@"public.munki"]
        || [fid isEqualToString:@"public.submenu"];
}

- (BOOL)functionSupportsNotifications:(NSString *)fid {
    return [self functionSupportsStateNotifications:fid]
        || [fid isEqualToString:@"public.command"];
}

/// Which notification keys can actually fire for the current type/kind.
- (NSSet<NSString *> *)applicableNotificationKeys {
    NSString *fid = [self selectedFunctionIdentifier];
    if ([fid isEqualToString:@"public.command"]) {
        return [NSSet setWithObject:@"notificationOnCompletion"];
    }
    if (![self functionSupportsStateNotifications:fid]) {
        return [NSSet set];
    }
    // Scripts and submenus can surface any state.
    if ([fid isEqualToString:@"public.script.item"] || [fid isEqualToString:@"public.submenu"]) {
        return [NSSet setWithArray:@[
            @"notificationWhenStateTurnOK",
            @"notificationWhenStateTurnWarning",
            @"notificationWhenStateTurnError",
            @"notificationWhenStateTurnUnavailable",
            @"notificationWhenStateTurnNone",
        ]];
    }
    // HTTP test defaults to OK / Warning / Error / Unavailable; prefs can remap failed/unmatching to any state.
    if ([fid isEqualToString:@"public.test.http"]) {
        return [NSSet setWithArray:@[
            @"notificationWhenStateTurnOK",
            @"notificationWhenStateTurnWarning",
            @"notificationWhenStateTurnError",
            @"notificationWhenStateTurnUnavailable",
            @"notificationWhenStateTurnNone",
        ]];
    }
    if ([fid isEqualToString:@"public.munki"]) {
        NSString *kind = [self selectedInfoKind].lowercaseString;
        if ([kind isEqualToString:@"pending"]) {
            // None (no updates), Warning (pending), Error (restart required). Never OK/Unavailable.
            return [NSSet setWithArray:@[
                @"notificationWhenStateTurnWarning",
                @"notificationWhenStateTurnError",
                @"notificationWhenStateTurnNone",
            ]];
        }
        // Manifest: None when present, Error when missing.
        return [NSSet setWithArray:@[
            @"notificationWhenStateTurnError",
            @"notificationWhenStateTurnNone",
        ]];
    }
    if ([fid isEqualToString:@"public.system.info"]) {
        NSString *kind = [self selectedInfoKind].lowercaseString;
        if ([kind isEqualToString:@"hostname"]) {
            // Hostname never changes testState (always None) — no useful notifications.
            return [NSSet set];
        }
        if ([kind isEqualToString:@"uptime"] || [kind isEqualToString:@"memory"] || [kind isEqualToString:@"storage"]
            || [kind isEqualToString:@"wifi"]) {
            // OK / Warning / Error / Unavailable. Never None.
            return [NSSet setWithArray:@[
                @"notificationWhenStateTurnOK",
                @"notificationWhenStateTurnWarning",
                @"notificationWhenStateTurnError",
                @"notificationWhenStateTurnUnavailable",
            ]];
        }
        if ([kind isEqualToString:@"ip"]) {
            // OK / Error / Unavailable / None (hide-when-offline mode). No Warning.
            return [NSSet setWithArray:@[
                @"notificationWhenStateTurnOK",
                @"notificationWhenStateTurnError",
                @"notificationWhenStateTurnUnavailable",
                @"notificationWhenStateTurnNone",
            ]];
        }
        if ([kind isEqualToString:@"ethernet"]) {
            // OK when linked; None when hidden (no link). No Warning/Error/Unavailable.
            return [NSSet setWithArray:@[
                @"notificationWhenStateTurnOK",
                @"notificationWhenStateTurnNone",
            ]];
        }
    }
    return [NSSet set];
}

- (NSButton *)notificationSwitchWithTitle:(NSString *)title toolTip:(NSString *)toolTip {
    NSButton *button = [[NSButton alloc] initWithFrame:NSMakeRect(0, 0, 80, 22)];
    button.buttonType = NSButtonTypeSwitch;
    button.title = title;
    button.target = self;
    button.action = @selector(notificationSwitchChanged:);
    button.toolTip = toolTip;
    return button;
}

- (CGFloat)placeNotifySwitch:(NSButton *)toggle field:(NSTextField *)field atY:(CGFloat)y width:(CGFloat)width {
    return [self placeAlertRowWithSwitch:toggle
                                   field:field
                          thresholdLabel:nil
                          thresholdField:nil
                                     atY:y
                                   width:width];
}

/// One Alerts row: optional on/off + message, and/or threshold control on the right.
- (CGFloat)placeAlertRowWithSwitch:(NSButton *)toggle
                             field:(NSTextField *)field
                    thresholdLabel:(NSTextField *)thresholdLabel
                    thresholdField:(NSTextField *)thresholdField
                               atY:(CGFloat)y
                             width:(CGFloat)width {
    const CGFloat controlX = kHITConfigInspectorControlX;
    const CGFloat threshFieldW = 56;
    const CGFloat threshLabelW = 28;
    const CGFloat gap = 8;
    BOOL hasToggle = (toggle != nil);
    BOOL hasField = (field != nil);
    BOOL hasThreshold = (thresholdField != nil);

    if (hasToggle) {
        toggle.hidden = NO;
        toggle.frame = NSMakeRect(16, y + 1, kHITConfigInspectorLabelWidth, 22);
    }

    CGFloat messageWidth = width;
    if (hasThreshold) {
        messageWidth = MAX(120, width - threshLabelW - gap - threshFieldW - gap);
        CGFloat tx = controlX + (hasField ? messageWidth + gap : 0);
        if (!hasField) {
            // Threshold-only row still starts at the control column.
            tx = controlX;
        }
        thresholdLabel.hidden = NO;
        thresholdField.hidden = NO;
        thresholdLabel.frame = NSMakeRect(tx, y + 4, threshLabelW, 16);
        thresholdField.frame = NSMakeRect(tx + threshLabelW + 4, y, threshFieldW, 24);
        if (!hasField) {
            // Stretch a bit when there's no message field.
            thresholdField.frame = NSMakeRect(controlX + threshLabelW + 4, y, 80, 24);
            thresholdLabel.frame = NSMakeRect(controlX, y + 4, threshLabelW, 16);
        }
    } else if (thresholdLabel) {
        thresholdLabel.hidden = YES;
    }

    if (hasField) {
        field.hidden = NO;
        field.frame = NSMakeRect(controlX, y, hasThreshold ? messageWidth : width, 24);
    }

    return y + 24 + 12;
}

/// Short name used inside default notification bodies (title, else type/kind).
- (NSString *)notificationSubjectLabel {
    NSString *title = [self.titleField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (title.length > 0) {
        return title;
    }
    NSString *fid = [self selectedFunctionIdentifier];
    if ([fid isEqualToString:@"public.system.info"]) {
        NSString *kind = [self selectedInfoKind].lowercaseString;
        NSDictionary *labels = @{
            @"hostname": @"Hostname",
            @"ip": @"IP address",
            @"wifi": @"Wi‑Fi",
            @"ethernet": @"Ethernet",
            @"storage": @"Storage",
            @"uptime": @"Uptime",
            @"memory": @"Memory pressure",
        };
        return labels[kind] ?: @"System info";
    }
    if ([fid isEqualToString:@"public.munki"]) {
        NSString *kind = [self selectedInfoKind].lowercaseString;
        if ([kind isEqualToString:@"pending"]) {
            return @"Pending Munki updates";
        }
        if ([kind isEqualToString:@"manifest"]) {
            return @"Munki manifest";
        }
        return @"Munki";
    }
    if ([fid isEqualToString:@"public.test.http"]) {
        return @"HTTP check";
    }
    if ([fid isEqualToString:@"public.script.item"]) {
        NSString *script = [self.keyField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (script.length > 0) {
            return [self humanizedScriptName:script.lastPathComponent];
        }
        return @"Script check";
    }
    if ([fid isEqualToString:@"public.submenu"]) {
        return @"Submenu";
    }
    if ([fid isEqualToString:@"public.command"]) {
        return @"Command";
    }
    return @"Menu item";
}

- (NSString *)defaultNotificationMessageForKey:(NSString *)key {
    NSString *subject = [self notificationSubjectLabel];
    NSString *fid = [self selectedFunctionIdentifier];
    NSString *kind = [fid isEqualToString:@"public.system.info"] || [fid isEqualToString:@"public.munki"]
        ? [self selectedInfoKind].lowercaseString
        : @"";

    // Keep bodies short — Notification Center truncates long informativeText.
    if ([fid isEqualToString:@"public.system.info"] && [kind isEqualToString:@"uptime"]) {
        NSInteger warnDays = [self resolvedWarnThresholdForKind:kind];
        NSInteger errorDays = [self resolvedErrorThresholdForKind:kind];
        if ([key isEqualToString:@"notificationWhenStateTurnOK"]) {
            return @"Restarted recently enough.";
        }
        if ([key isEqualToString:@"notificationWhenStateTurnWarning"]) {
            return [NSString stringWithFormat:@"On for %ld+ days. Restart when you can.", (long)warnDays];
        }
        if ([key isEqualToString:@"notificationWhenStateTurnError"]) {
            return [NSString stringWithFormat:@"On for %ld+ days. Please restart soon.", (long)errorDays];
        }
        if ([key isEqualToString:@"notificationWhenStateTurnUnavailable"]) {
            return @"Couldn't check last restart.";
        }
    }
    if ([fid isEqualToString:@"public.system.info"] && [kind isEqualToString:@"memory"]) {
        NSInteger warnPct = [self resolvedWarnThresholdForKind:kind];
        NSInteger errorPct = [self resolvedErrorThresholdForKind:kind];
        if ([key isEqualToString:@"notificationWhenStateTurnOK"]) {
            return @"Memory looks fine.";
        }
        if ([key isEqualToString:@"notificationWhenStateTurnWarning"]) {
            return [NSString stringWithFormat:@"Memory over %ld%%. Close apps or browser tabs.", (long)warnPct];
        }
        if ([key isEqualToString:@"notificationWhenStateTurnError"]) {
            return [NSString stringWithFormat:@"Memory critical (over %ld%%). Close apps/tabs or restart.", (long)errorPct];
        }
        if ([key isEqualToString:@"notificationWhenStateTurnUnavailable"]) {
            return @"Couldn't check memory use.";
        }
    }
    if ([fid isEqualToString:@"public.system.info"] && [kind isEqualToString:@"storage"]) {
        NSInteger warnGB = [self resolvedWarnThresholdForKind:kind];
        NSInteger errorGB = [self resolvedErrorThresholdForKind:kind];
        if ([key isEqualToString:@"notificationWhenStateTurnOK"]) {
            return @"Enough free disk space.";
        }
        if ([key isEqualToString:@"notificationWhenStateTurnWarning"]) {
            return [NSString stringWithFormat:@"Under %ld GB free. Delete or move files.", (long)warnGB];
        }
        if ([key isEqualToString:@"notificationWhenStateTurnError"]) {
            return [NSString stringWithFormat:@"Under %ld GB free. Free space soon.", (long)errorGB];
        }
        if ([key isEqualToString:@"notificationWhenStateTurnUnavailable"]) {
            return @"Couldn't check disk space.";
        }
    }
    if ([fid isEqualToString:@"public.system.info"] && [kind isEqualToString:@"wifi"]) {
        NSInteger warnSNR = [self resolvedWarnThresholdForKind:kind];
        NSInteger errorSNR = [self resolvedErrorThresholdForKind:kind];
        if ([key isEqualToString:@"notificationWhenStateTurnOK"]) {
            return @"Wi‑Fi signal looks good.";
        }
        if ([key isEqualToString:@"notificationWhenStateTurnWarning"]) {
            return [NSString stringWithFormat:@"Wi‑Fi weak (under %ld dB). Move closer.", (long)warnSNR];
        }
        if ([key isEqualToString:@"notificationWhenStateTurnError"]) {
            return [NSString stringWithFormat:@"Wi‑Fi very weak (under %ld dB).", (long)errorSNR];
        }
        if ([key isEqualToString:@"notificationWhenStateTurnUnavailable"]) {
            return @"Wi‑Fi off or disconnected.";
        }
    }
    if ([fid isEqualToString:@"public.system.info"] && [kind isEqualToString:@"ip"]) {
        if ([key isEqualToString:@"notificationWhenStateTurnOK"]) {
            return @"Network address is back.";
        }
        if ([key isEqualToString:@"notificationWhenStateTurnError"]) {
            return @"No network address. Check Wi‑Fi or Ethernet.";
        }
        if ([key isEqualToString:@"notificationWhenStateTurnUnavailable"]) {
            return @"No network address right now.";
        }
        if ([key isEqualToString:@"notificationWhenStateTurnNone"]) {
            return @"Network address hidden.";
        }
    }
    if ([fid isEqualToString:@"public.system.info"] && [kind isEqualToString:@"ethernet"]) {
        if ([key isEqualToString:@"notificationWhenStateTurnOK"]) {
            return @"Ethernet connected.";
        }
        if ([key isEqualToString:@"notificationWhenStateTurnNone"]) {
            return @"Ethernet disconnected.";
        }
    }
    if ([fid isEqualToString:@"public.test.http"]) {
        if ([key isEqualToString:@"notificationWhenStateTurnOK"]) {
            return [NSString stringWithFormat:@"%@ is working again.", subject];
        }
        if ([key isEqualToString:@"notificationWhenStateTurnWarning"]) {
            return [NSString stringWithFormat:@"%@ isn't responding as expected.", subject];
        }
        if ([key isEqualToString:@"notificationWhenStateTurnError"]) {
            return [NSString stringWithFormat:@"%@ failed. Check your connection.", subject];
        }
        if ([key isEqualToString:@"notificationWhenStateTurnUnavailable"]) {
            return [NSString stringWithFormat:@"Network unavailable for %@.", subject];
        }
        if ([key isEqualToString:@"notificationWhenStateTurnNone"]) {
            return [NSString stringWithFormat:@"%@ cleared.", subject];
        }
    }
    if ([fid isEqualToString:@"public.munki"] && [kind isEqualToString:@"pending"]) {
        if ([key isEqualToString:@"notificationWhenStateTurnWarning"]) {
            return @"Updates waiting. Open Managed Software Center.";
        }
        if ([key isEqualToString:@"notificationWhenStateTurnError"]) {
            return @"Updates need a restart. Save work, then restart.";
        }
        if ([key isEqualToString:@"notificationWhenStateTurnNone"]) {
            return @"No updates waiting.";
        }
    }
    if ([fid isEqualToString:@"public.munki"]) {
        if ([key isEqualToString:@"notificationWhenStateTurnError"]) {
            return @"Software catalog missing. Contact IT.";
        }
        if ([key isEqualToString:@"notificationWhenStateTurnNone"]) {
            return @"Software catalog looks normal.";
        }
    }

    if ([key isEqualToString:@"notificationWhenStateTurnOK"]) {
        return [NSString stringWithFormat:@"%@ looks OK again.", subject];
    }
    if ([key isEqualToString:@"notificationWhenStateTurnWarning"]) {
        return [NSString stringWithFormat:@"%@ needs attention.", subject];
    }
    if ([key isEqualToString:@"notificationWhenStateTurnError"]) {
        return [NSString stringWithFormat:@"%@ reported a problem.", subject];
    }
    if ([key isEqualToString:@"notificationWhenStateTurnUnavailable"]) {
        return [NSString stringWithFormat:@"%@ unavailable.", subject];
    }
    if ([key isEqualToString:@"notificationWhenStateTurnNone"]) {
        return [NSString stringWithFormat:@"%@ cleared.", subject];
    }
    if ([key isEqualToString:@"notificationOnCompletion"]) {
        return [NSString stringWithFormat:@"%@ finished.", subject];
    }
    return @"";
}

- (NSArray<NSArray *> *)notificationControlRows {
    if ([[self selectedFunctionIdentifier] isEqualToString:@"public.command"]) {
        // Reuse the first Alerts row (same switch + message layout as OK/Warning/…).
        return @[
            @[self.notifyOKSwitch, self.notifyOKField, @"notificationOnCompletion"],
        ];
    }
    return @[
        @[self.notifyOKSwitch, self.notifyOKField, @"notificationWhenStateTurnOK"],
        @[self.notifyWarningSwitch, self.notifyWarningField, @"notificationWhenStateTurnWarning"],
        @[self.notifyErrorSwitch, self.notifyErrorField, @"notificationWhenStateTurnError"],
        @[self.notifyUnavailableSwitch, self.notifyUnavailableField, @"notificationWhenStateTurnUnavailable"],
        @[self.notifyNoneSwitch, self.notifyNoneField, @"notificationWhenStateTurnNone"],
    ];
}

- (void)configureNotificationControlsVisible:(BOOL)show settings:(NSDictionary *)settings {
    NSSet<NSString *> *applicable = show ? [self applicableNotificationKeys] : [NSSet set];
    BOOL isCommand = [[self selectedFunctionIdentifier] isEqualToString:@"public.command"];
    self.notifyOKSwitch.title = isCommand ? @"Done" : @"OK";
    self.notifyOKSwitch.toolTip = isCommand
        ? @"notifyOnCompletion / notificationOnCompletion — banner when the command finishes"
        : @"notificationWhenStateTurnOK — banner title is the menu item title";
    self.notifyOKField.toolTip = self.notifyOKSwitch.toolTip;

    // Always reset every Alerts row (Command only uses Done; leftover state rows must hide).
    NSArray<NSArray *> *allRows = @[
        @[self.notifyOKSwitch, self.notifyOKField, isCommand ? @"notificationOnCompletion" : @"notificationWhenStateTurnOK"],
        @[self.notifyWarningSwitch, self.notifyWarningField, @"notificationWhenStateTurnWarning"],
        @[self.notifyErrorSwitch, self.notifyErrorField, @"notificationWhenStateTurnError"],
        @[self.notifyUnavailableSwitch, self.notifyUnavailableField, @"notificationWhenStateTurnUnavailable"],
        @[self.notifyNoneSwitch, self.notifyNoneField, @"notificationWhenStateTurnNone"],
    ];
    for (NSArray *row in allRows) {
        NSButton *toggle = row[0];
        NSTextField *field = row[1];
        NSString *key = row[2];
        BOOL rowVisible = [applicable containsObject:key];
        toggle.hidden = !rowVisible;
        field.hidden = !rowVisible;
        toggle.enabled = rowVisible;
        if (!rowVisible) {
            toggle.state = NSControlStateValueOff;
            field.stringValue = @"";
            field.enabled = NO;
            continue;
        }
        NSString *stored = [self resolvedTitleFromValue:settings[key]];
        NSString *fallback = [self defaultNotificationMessageForKey:key];
        BOOL enabled = stored.length > 0;
        if ([key isEqualToString:@"notificationOnCompletion"]) {
            enabled = enabled || [settings[@"notifyOnCompletion"] boolValue];
        }
        toggle.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;
        field.stringValue = stored.length > 0 ? stored : fallback;
        field.placeholderString = fallback;
        field.enabled = enabled;
    }
}

/// Keep disabled rows’ preview text in sync when title / type / kind changes.
- (void)refreshDisabledNotificationDefaultMessages {
    for (NSArray *row in [self notificationControlRows]) {
        NSButton *toggle = row[0];
        NSTextField *field = row[1];
        NSString *key = row[2];
        if (field.hidden) {
            continue;
        }
        NSString *fallback = [self defaultNotificationMessageForKey:key];
        field.placeholderString = fallback;
        if (toggle.state != NSControlStateValueOn) {
            field.stringValue = fallback;
        }
    }
}

- (void)notificationSwitchChanged:(id)sender {
    if (self.updatingUI) {
        return;
    }
    for (NSArray *row in [self notificationControlRows]) {
        NSButton *toggle = row[0];
        NSTextField *field = row[1];
        NSString *key = row[2];
        BOOL on = toggle.state == NSControlStateValueOn;
        field.enabled = on && !toggle.hidden;
        if (on && field.stringValue.length == 0) {
            field.stringValue = [self defaultNotificationMessageForKey:key];
        }
    }
    [self commitInspectorToSelectedItem];
}

- (void)writeNotificationFromSwitch:(NSButton *)toggle
                              field:(NSTextField *)field
                                key:(NSString *)key
                     defaultMessage:(NSString *)defaultMessage
                       intoSettings:(NSMutableDictionary *)settings
                           existing:(id)existing {
    if (toggle.state != NSControlStateValueOn) {
        [settings removeObjectForKey:key];
        return;
    }
    NSString *text = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length == 0) {
        text = defaultMessage;
    }
    [self writeOptionalLocalizedString:text key:key intoSettings:settings existing:existing];
}

- (void)writeOptionalLocalizedString:(NSString *)text
                                 key:(NSString *)key
                        intoSettings:(NSMutableDictionary *)settings
                            existing:(id)existing {
    if (text.length == 0) {
        [settings removeObjectForKey:key];
        return;
    }
    if ([existing isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *dict = [existing mutableCopy];
        dict[@"en"] = text;
        NSString *lang = [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode];
        if (lang.length > 0) {
            dict[lang] = text;
        }
        settings[key] = dict;
        return;
    }
    settings[key] = text;
}

- (void)writeTitle:(NSString *)title intoSettings:(NSMutableDictionary *)settings {
    id existing = settings[kHITConfigTitle];
    if (title.length == 0) {
        [settings removeObjectForKey:kHITConfigTitle];
        return;
    }
    // Preserve localized dicts: update en (and current language) instead of flattening.
    if ([existing isKindOfClass:[NSMutableDictionary class]] || [existing isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *dict = [existing isKindOfClass:[NSMutableDictionary class]]
            ? existing
            : [existing mutableCopy];
        dict[@"en"] = title;
        NSString *lang = [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode];
        if (lang.length > 0) {
            dict[lang] = title;
        }
        // Prefer settings.tooltip; drop legacy title.tooltip if present.
        [dict removeObjectForKey:@"tooltip"];
        settings[kHITConfigTitle] = dict;
        return;
    }
    settings[kHITConfigTitle] = title;
}

- (void)writeTooltip:(NSString *)tooltip intoSettings:(NSMutableDictionary *)settings {
    if (tooltip.length == 0) {
        [settings removeObjectForKey:@"tooltip"];
    } else {
        settings[@"tooltip"] = tooltip;
    }
    // Normalize away legacy title.tooltip
    id title = settings[kHITConfigTitle];
    if ([title isKindOfClass:[NSMutableDictionary class]]) {
        [title removeObjectForKey:@"tooltip"];
    } else if ([title isKindOfClass:[NSDictionary class]] && title[@"tooltip"]) {
        NSMutableDictionary *dict = [title mutableCopy];
        [dict removeObjectForKey:@"tooltip"];
        settings[kHITConfigTitle] = dict;
    }
}

- (void)writeIconSettingsIntoSettings:(NSMutableDictionary *)settings {
    NSString *fid = [self selectedFunctionIdentifier];
    if ([fid isEqualToString:@"public.separator"] || [fid isEqualToString:@"public.quit"]) {
        [settings removeObjectForKey:@"imageBaseName"];
        [settings removeObjectForKey:@"imagePath"];
        [settings removeObjectForKey:@"noIcon"];
        return;
    }
    HITConfigIconMode mode = [self currentIconMode];
    NSString *value = [self.iconValueField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [settings removeObjectForKey:@"imageBaseName"];
    [settings removeObjectForKey:@"imagePath"];
    [settings removeObjectForKey:@"noIcon"];
    if (mode == HITConfigIconModeNone) {
        settings[@"noIcon"] = @YES;
    } else if (mode == HITConfigIconModeImageName && value.length > 0) {
        settings[@"imageBaseName"] = value;
    } else if (mode == HITConfigIconModeFilePath && value.length > 0) {
        settings[@"imagePath"] = value;
    }
}

- (void)browseIconPath:(id)sender {
    if (!self.selectedItem || self.iconBrowseButton.hidden) {
        return;
    }
    [self runOpenPanelForField:self.iconValueField
                         title:@"Choose a menu item icon (PNG) or an application"
                  allowedTypes:@[@"png", @"tiff", @"tif", @"icns", @"jpg", @"jpeg", @"gif", @"app"]
                 directoryHint:@"/Library/Application Support/com.github.ygini.hello-it/CustomImageForItem"
            canChooseDirectories:NO
             treatPackagesAsDirs:NO
                    completion:^(NSString *path) {
        [self applyIconPathFromBrowseOrDrop:path];
    }];
}

- (void)revealIconPath:(id)sender {
    [self revealPathInFinder:[self resolvedIconFilesystemPathForReveal]];
}

- (void)revealFilePath:(id)sender {
    [self revealPathInFinder:self.fileField.stringValue];
}

- (void)revealKeyPath:(id)sender {
    [self revealPathInFinder:[self resolvedKeyFieldFilesystemPath]];
}

- (void)browseFilePath:(id)sender {
    if (!self.selectedItem || self.fileField.hidden) {
        return;
    }
    [self runOpenPanelForField:self.fileField
                         title:@"Choose a file to open with the application"
                  allowedTypes:nil
                 directoryHint:NSHomeDirectory()
            canChooseDirectories:YES
             treatPackagesAsDirs:YES
                    completion:^(NSString *path) {
        [self applyFilePathFromBrowseOrDrop:path];
    }];
}

- (void)browseKeyPath:(id)sender {
    if (!self.selectedItem || self.keyBrowseButton.hidden) {
        return;
    }
    NSString *fid = [self selectedFunctionIdentifier];
    if ([fid isEqualToString:@"public.script.item"]) {
        NSString *scripts = @"/Library/Application Support/com.github.ygini.hello-it/CustomScripts";
        [self runOpenPanelForField:self.keyField
                             title:@"Choose a Hello IT script"
                      allowedTypes:nil
                     directoryHint:scripts
                canChooseDirectories:NO
                 treatPackagesAsDirs:NO
                        completion:^(NSString *path) {
            [self applyKeyPathFromBrowseOrDrop:path];
        }];
        return;
    }
    if ([fid isEqualToString:@"public.open.application"]) {
        [self runOpenPanelForField:self.keyField
                             title:@"Choose an application"
                      allowedTypes:@[@"app"]
                     directoryHint:@"/Applications"
                canChooseDirectories:NO
             treatPackagesAsDirs:NO
                        completion:^(NSString *path) {
            [self applyKeyPathFromBrowseOrDrop:path];
        }];
        return;
    }
    if ([fid isEqualToString:@"public.open.resource"]) {
        [self runOpenPanelForField:self.keyField
                             title:@"Choose a local file or folder to open"
                      allowedTypes:nil
                     directoryHint:NSHomeDirectory()
                canChooseDirectories:YES
                 treatPackagesAsDirs:YES
                        completion:^(NSString *path) {
            [self applyKeyPathFromBrowseOrDrop:path];
        }];
    }
}

- (NSImage *)customMenuImageForSettings:(NSDictionary *)settings {
    if (![settings isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *imagePath = settings[@"imagePath"];
    if (imagePath.length == 0) {
        NSString *base = settings[@"imageBaseName"];
        if (base.length == 0) {
            return nil;
        }
        NSString *folder = @"/Library/Application Support/com.github.ygini.hello-it/CustomImageForItem";
        NSString *osxMode = [[NSUserDefaults standardUserDefaults] stringForKey:@"AppleInterfaceStyle"];
        if ([osxMode isEqualToString:@"Dark"]) {
            NSString *darkPath = [[folder stringByAppendingPathComponent:[base stringByAppendingString:@"-dark"]] stringByAppendingPathExtension:@"png"];
            if ([[NSFileManager defaultManager] fileExistsAtPath:darkPath]) {
                imagePath = darkPath;
            }
        }
        if (imagePath.length == 0) {
            imagePath = [[folder stringByAppendingPathComponent:base] stringByAppendingPathExtension:@"png"];
        }
    }
    if (imagePath.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
        return nil;
    }
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:imagePath];
    if (!image) {
        // .app (or other) path — use workspace icon (same as HITSimplePlugin).
        image = [[NSWorkspace sharedWorkspace] iconForFile:imagePath];
    }
    if (!image) {
        return nil;
    }
    image = [image copy];
    image.size = NSMakeSize(12, 12);
    image.template = NO;
    return image;
}

- (NSImage *)applicationIconForSettings:(NSDictionary *)settings {
    if (![settings isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    NSString *appPath = nil;
    NSString *appURL = settings[@"appURL"];
    if ([appURL isKindOfClass:[NSString class]] && appURL.length > 0) {
        appPath = appURL;
    } else {
        NSString *appName = settings[@"app"];
        if ([appName isKindOfClass:[NSString class]] && appName.length > 0) {
            appPath = [[NSWorkspace sharedWorkspace] fullPathForApplication:appName];
        }
    }
    if (appPath.length == 0) {
        return nil;
    }
    NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:appPath];
    if (!icon) {
        return nil;
    }
    icon = [icon copy];
    icon.size = NSMakeSize(12, 12);
    icon.template = NO;
    return icon;
}

- (NSArray<NSString *> *)shellSplit:(NSString *)string {
    NSMutableArray *parts = [NSMutableArray array];
    NSArray *raw = [string componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    for (NSString *part in raw) {
        if (part.length > 0) {
            [parts addObject:part];
        }
    }
    return [parts copy];
}

- (void)typeChanged:(id)sender {
    [self commitInspectorToSelectedItem];
    [self populateInspector];
    [self reloadOutlinePreservingSelection];
}

- (void)infoKindChanged:(id)sender {
    if (self.updatingUI || !self.selectedItem) {
        return;
    }
    // Rebuild dependent menus for the new kind, then commit.
    NSMutableDictionary *settings = self.selectedItem[kHITConfigSettings];
    if (![settings isKindOfClass:[NSMutableDictionary class]]) {
        settings = [NSMutableDictionary dictionary];
        self.selectedItem[kHITConfigSettings] = settings;
    }
    NSString *kind = [self selectedInfoKind];
    NSString *fid = [self selectedFunctionIdentifier];
    if ([fid isEqualToString:@"public.send.email"]) {
        settings[@"mailer"] = ([kind isEqualToString:@"gmail"] ? @"gmail" : @"default");
        [self reflowInspectorFromActionSection];
        [self commitInspectorToSelectedItem];
        [self reloadOutlinePreservingSelection];
        return;
    }

    settings[@"kind"] = kind;

    if ([fid isEqualToString:@"public.munki"]) {
        self.infoOptionPopup.hidden = YES;
        self.infoOptionLabel.hidden = YES;
        self.infoInterfacePopup.hidden = YES;
        self.infoInterfaceLabel.hidden = YES;
        [self configureThresholdFieldsForKind:nil settings:nil];
        [self configureNotificationControlsVisible:YES settings:settings];
        [self reflowInspectorFromActionSection];
        [self commitInspectorToSelectedItem];
        [self reloadOutlinePreservingSelection];
        return;
    }

    [self rebuildInfoOptionPopupForKind:kind settings:settings];
    BOOL needsInterface = [kind isEqualToString:@"ip"] || [kind isEqualToString:@"ethernet"];
    self.infoInterfacePopup.hidden = !needsInterface;
    self.infoInterfaceLabel.hidden = !needsInterface;
    if (needsInterface) {
        [self rebuildInfoInterfacePopupWithSettings:settings];
    }
    [self configureThresholdFieldsForKind:kind settings:settings];
    [self configureNotificationControlsVisible:[self functionSupportsNotifications:fid] settings:settings];
    [self reflowInspectorFromActionSection];
    [self commitInspectorToSelectedItem];
    [self reloadOutlinePreservingSelection];
}

- (BOOL)kindSupportsThresholdFields:(NSString *)kind {
    kind = kind.lowercaseString;
    return [kind isEqualToString:@"uptime"]
        || [kind isEqualToString:@"memory"]
        || [kind isEqualToString:@"storage"]
        || [kind isEqualToString:@"wifi"];
}

- (NSInteger)defaultWarnThresholdForKind:(NSString *)kind {
    kind = kind.lowercaseString;
    if ([kind isEqualToString:@"memory"]) return 70;
    if ([kind isEqualToString:@"storage"]) return 50;
    if ([kind isEqualToString:@"wifi"]) return 25;
    return 7; // uptime days
}

- (NSInteger)defaultErrorThresholdForKind:(NSString *)kind {
    kind = kind.lowercaseString;
    if ([kind isEqualToString:@"memory"]) return 85;
    if ([kind isEqualToString:@"storage"]) return 10;
    if ([kind isEqualToString:@"wifi"]) return 15;
    return 14; // uptime days
}

- (NSInteger)resolvedWarnThresholdForKind:(NSString *)kind {
    NSInteger value = [self.uptimeWarnField.stringValue integerValue];
    return value > 0 ? value : [self defaultWarnThresholdForKind:kind];
}

- (NSInteger)resolvedErrorThresholdForKind:(NSString *)kind {
    NSInteger value = [self.uptimeErrorField.stringValue integerValue];
    return value > 0 ? value : [self defaultErrorThresholdForKind:kind];
}

- (void)configureThresholdFieldsForKind:(NSString *)kind settings:(NSDictionary *)settings {
    kind = kind.lowercaseString;
    BOOL show = [self kindSupportsThresholdFields:kind];
    self.uptimeWarnField.hidden = !show;
    self.uptimeWarnLabel.hidden = !show;
    self.uptimeErrorField.hidden = !show;
    self.uptimeErrorLabel.hidden = !show;
    self.uptimeWarnField.enabled = show;
    self.uptimeErrorField.enabled = show;
    if (!show) {
        self.uptimeWarnField.stringValue = @"";
        self.uptimeErrorField.stringValue = @"";
        return;
    }

    NSString *warnKey = @"warnDays";
    NSString *errorKey = @"errorDays";
    NSString *warnLabel = @"≥";
    NSString *errorLabel = @"≥";
    NSString *warnPlaceholder = @"7 days";
    NSString *errorPlaceholder = @"14 days";
    NSString *warnTip = @"Warning when uptime reaches this many days (default 7)";
    NSString *errorTip = @"Error when uptime reaches this many days (default 14)";

    if ([kind isEqualToString:@"memory"]) {
        warnKey = @"warnPercent";
        errorKey = @"errorPercent";
        warnLabel = @"≥";
        errorLabel = @"≥";
        warnPlaceholder = @"70%";
        errorPlaceholder = @"85%";
        warnTip = @"Warning when memory pressure % reaches this value (default 70)";
        errorTip = @"Error when memory pressure % reaches this value (default 85)";
    } else if ([kind isEqualToString:@"storage"]) {
        warnKey = @"warnBelowGB";
        errorKey = @"errorBelowGB";
        warnLabel = @"<";
        errorLabel = @"<";
        warnPlaceholder = @"50 GB";
        errorPlaceholder = @"10 GB";
        warnTip = @"Warning when free disk space falls below this many GB (default 50)";
        errorTip = @"Error when free disk space falls below this many GB (default 10)";
    } else if ([kind isEqualToString:@"wifi"]) {
        warnKey = @"warnBelowSNR";
        errorKey = @"errorBelowSNR";
        warnLabel = @"<";
        errorLabel = @"<";
        warnPlaceholder = @"25 dB";
        errorPlaceholder = @"15 dB";
        warnTip = @"Warning when Wi‑Fi SNR (dB) falls below this value (default 25)";
        errorTip = @"Error when Wi‑Fi SNR (dB) falls below this value (default 15)";
    }

    self.uptimeWarnLabel.stringValue = warnLabel;
    self.uptimeErrorLabel.stringValue = errorLabel;
    self.uptimeWarnField.placeholderString = warnPlaceholder;
    self.uptimeErrorField.placeholderString = errorPlaceholder;
    self.uptimeWarnField.toolTip = warnTip;
    self.uptimeErrorField.toolTip = errorTip;

    id warn = settings[warnKey];
    id error = settings[errorKey];
    self.uptimeWarnField.stringValue = warn ? [NSString stringWithFormat:@"%@", warn] : @"";
    self.uptimeErrorField.stringValue = error ? [NSString stringWithFormat:@"%@", error] : @"";
}

- (void)writeThresholdFieldsForKind:(NSString *)kind intoSettings:(NSMutableDictionary *)settings {
    kind = kind.lowercaseString;
    NSInteger warn = [self.uptimeWarnField.stringValue integerValue];
    NSInteger error = [self.uptimeErrorField.stringValue integerValue];
    if ([kind isEqualToString:@"uptime"]) {
        if (warn > 0) settings[@"warnDays"] = @(warn);
        if (error > 0) settings[@"errorDays"] = @(error);
    } else if ([kind isEqualToString:@"memory"]) {
        if (warn > 0) settings[@"warnPercent"] = @(warn);
        if (error > 0) settings[@"errorPercent"] = @(error);
    } else if ([kind isEqualToString:@"storage"]) {
        if (warn > 0) settings[@"warnBelowGB"] = @(warn);
        if (error > 0) settings[@"errorBelowGB"] = @(error);
    } else if ([kind isEqualToString:@"wifi"]) {
        if (warn > 0) settings[@"warnBelowSNR"] = @(warn);
        if (error > 0) settings[@"errorBelowSNR"] = @(error);
    }
}

- (void)infoOptionChanged:(id)sender {
    [self commitInspectorToSelectedItem];
    [self reloadOutlinePreservingSelection];
}

- (void)flagsChanged:(id)sender {
    [self commitInspectorToSelectedItem];
}

- (void)controlTextDidEndEditing:(NSNotification *)obj {
    [self commitInspectorToSelectedItem];
    [self updateRevealButtonsEnabled];
    if (obj.object == self.titleField || obj.object == self.keyField
        || obj.object == self.uptimeWarnField || obj.object == self.uptimeErrorField) {
        [self refreshDisabledNotificationDefaultMessages];
    }
}

#pragma mark - Add / remove

- (NSMutableDictionary *)newBlankItem {
    return [@{
        kHITConfigFunctionIdentifier: @"public.title",
        kHITConfigSettings: [@{ kHITConfigTitle: @"New item" } mutableCopy]
    } mutableCopy];
}

- (void)addItem:(id)sender {
    [self commitInspectorToSelectedItem];
    NSMutableDictionary *selected = self.selectedItem;
    NSMutableArray *parentArray = self.rootContent;
    id parentItem = nil;

    if (selected) {
        parentItem = [self.outlineView parentForItem:selected];
        if (parentItem) {
            NSMutableDictionary *settings = parentItem[kHITConfigSettings];
            parentArray = settings[kHITConfigContent];
        }
    }

    NSMutableDictionary *item = [self newBlankItem];
    NSInteger insertAt = parentArray.count;
    if (selected && parentArray) {
        NSInteger idx = [parentArray indexOfObjectIdenticalTo:selected];
        if (idx != NSNotFound) {
            insertAt = idx + 1;
        }
    }
    [parentArray insertObject:item atIndex:insertAt];
    [self.outlineView reloadData];
    if (parentItem) {
        [self.outlineView expandItem:parentItem];
    }
    NSInteger row = [self.outlineView rowForItem:item];
    if (row >= 0) {
        [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    }
}

- (void)addChildItem:(id)sender {
    [self commitInspectorToSelectedItem];
    NSMutableDictionary *selected = self.selectedItem;
    if (!selected) {
        [self addItem:sender];
        return;
    }

    NSString *fid = selected[kHITConfigFunctionIdentifier];
    if (![fid isEqualToString:@"public.submenu"]) {
        selected[kHITConfigFunctionIdentifier] = @"public.submenu";
        NSMutableDictionary *settings = selected[kHITConfigSettings];
        if (![settings isKindOfClass:[NSMutableDictionary class]]) {
            settings = [NSMutableDictionary dictionary];
            selected[kHITConfigSettings] = settings;
        }
        if (![settings[kHITConfigContent] isKindOfClass:[NSMutableArray class]]) {
            settings[kHITConfigContent] = [NSMutableArray array];
        }
        if (!settings[kHITConfigTitle]) {
            settings[kHITConfigTitle] = @"Submenu";
        }
    }

    NSMutableDictionary *settings = selected[kHITConfigSettings];
    NSMutableArray *children = settings[kHITConfigContent];
    if (![children isKindOfClass:[NSMutableArray class]]) {
        children = [NSMutableArray array];
        settings[kHITConfigContent] = children;
    }
    NSMutableDictionary *child = [self newBlankItem];
    [children addObject:child];
    [self.outlineView reloadData];
    [self.outlineView expandItem:selected];
    NSInteger row = [self.outlineView rowForItem:child];
    if (row >= 0) {
        [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
    }
}

- (void)duplicateItem:(id)sender {
    [self commitInspectorToSelectedItem];
    NSMutableDictionary *selected = self.selectedItem;
    if (!selected) {
        NSBeep();
        return;
    }

    id parentItem = [self.outlineView parentForItem:selected];
    NSMutableArray *parentArray = self.rootContent;
    if (parentItem) {
        parentArray = parentItem[kHITConfigSettings][kHITConfigContent];
    }
    if (![parentArray isKindOfClass:[NSMutableArray class]]) {
        return;
    }

    NSMutableDictionary *copy = [self deepMutableCopyOfDictionary:selected];
    NSInteger idx = [parentArray indexOfObjectIdenticalTo:selected];
    NSInteger insertAt = (idx == NSNotFound) ? parentArray.count : idx + 1;
    [parentArray insertObject:copy atIndex:insertAt];

    [self reloadOutlinePreservingSelection];
    if (parentItem) {
        [self.outlineView expandItem:parentItem];
    }
    NSInteger row = [self.outlineView rowForItem:copy];
    if (row >= 0) {
        [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        self.selectedItem = copy;
        [self populateInspector];
    }
}

- (void)removeItem:(id)sender {
    NSMutableDictionary *selected = self.selectedItem;
    if (!selected) {
        return;
    }
    id parentItem = [self.outlineView parentForItem:selected];
    NSMutableArray *parentArray = self.rootContent;
    if (parentItem) {
        parentArray = parentItem[kHITConfigSettings][kHITConfigContent];
    }
    NSInteger idx = [parentArray indexOfObjectIdenticalTo:selected];
    [parentArray removeObjectIdenticalTo:selected];
    self.selectedItem = nil;
    [self.outlineView reloadData];
    if (parentItem) {
        [self.outlineView expandItem:parentItem];
    }
    // Select a neighbor so the inspector doesn’t go blank.
    if (parentArray.count > 0) {
        NSInteger nextIdx = MIN(MAX(idx, 0), (NSInteger)parentArray.count - 1);
        if (idx == NSNotFound) {
            nextIdx = 0;
        }
        id next = parentArray[nextIdx];
        NSInteger row = [self.outlineView rowForItem:next];
        if (row >= 0) {
            [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];
        }
    }
}

#pragma mark - Apply / export / import

- (void)apply:(id)sender {
    [self.window makeFirstResponder:nil];
    [self commitInspectorToSelectedItem];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    // Prefer 1.3+ shape; clear legacy root content so loadMenu uses functionIdentifier/settings.
    [defaults removeObjectForKey:kHITConfigContent];
    [defaults setObject:@"public.submenu" forKey:kHITConfigFunctionIdentifier];
    [defaults setObject:@{ kHITConfigContent: [self immutableCopyOfArray:self.rootContent] }
                 forKey:kHITConfigSettings];
    [defaults synchronize];

    os_log_info(OS_LOG_DEFAULT, "Configurator applied local preferences (%lu root items).",
                (unsigned long)self.rootContent.count);

    if (self.onApply) {
        self.onApply();
    }
}

- (NSData *)exportedPlistData:(NSError **)error {
    return [NSPropertyListSerialization dataWithPropertyList:[self immutableConfigurationRoot]
                                                      format:NSPropertyListXMLFormat_v1_0
                                                     options:0
                                                       error:error];
}

- (NSData *)exportedMobileconfigData:(NSError **)error {
    NSDictionary *prefs = [self immutableConfigurationRoot];
    NSString *uuid = [[NSUUID UUID] UUIDString];
    NSString *payloadUUID = [[NSUUID UUID] UUIDString];
    NSDictionary *profile = @{
        @"PayloadContent": @[
            @{
                @"PayloadType": @"com.apple.ManagedClient.preferences",
                @"PayloadVersion": @1,
                @"PayloadIdentifier": [@"com.github.ygini.Hello-IT.configuration." stringByAppendingString:payloadUUID],
                @"PayloadUUID": payloadUUID,
                @"PayloadEnabled": @YES,
                @"PayloadDisplayName": @"Hello IT",
                @"PayloadContent": @{
                    @"com.github.ygini.Hello-IT": @{
                        @"Forced": @[
                            @{ @"mcx_preference_settings": prefs }
                        ]
                    }
                }
            }
        ],
        @"PayloadDisplayName": @"Hello IT Configuration",
        @"PayloadIdentifier": [@"com.github.ygini.Hello-IT.profile." stringByAppendingString:uuid],
        @"PayloadRemovalDisallowed": @NO,
        @"PayloadType": @"Configuration",
        @"PayloadUUID": uuid,
        @"PayloadVersion": @1
    };
    return [NSPropertyListSerialization dataWithPropertyList:profile
                                                      format:NSPropertyListXMLFormat_v1_0
                                                     options:0
                                                       error:error];
}

- (NSData *)exportedBashScriptData:(NSError **)error {
    NSData *plistData = [self exportedPlistData:error];
    if (!plistData) {
        return nil;
    }
    NSString *plistXML = [[NSString alloc] initWithData:plistData encoding:NSUTF8StringEncoding];
    if (!plistXML) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileWriteInapplicableStringEncodingError
                                     userInfo:@{ NSLocalizedDescriptionKey: @"Could not encode preference plist as UTF-8." }];
        }
        return nil;
    }

    NSString *marker = [NSString stringWithFormat:@"HELLO_IT_PLIST_%@",
                        [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""]];
    NSMutableString *script = [NSMutableString string];
    [script appendString:@"#!/bin/bash\n"];
    [script appendString:@"# Hello IT configuration — generated by Configurator Mode\n"];
    [script appendString:@"# As normal user: imports into com.github.ygini.Hello-IT for that user.\n"];
    [script appendString:@"# As root (sudo): installs computer-wide /Library/Preferences/… (fleet).\n"];
    [script appendString:@"# Then reloads Hello IT via the LaunchAgent (never open(1) — that races KeepAlive and can leave two menu extras).\n"];
    [script appendString:@"# For MDM, prefer Export → Mobileconfig… instead.\n"];
    [script appendString:@"set -euo pipefail\n\n"];
    [script appendString:@"DOMAIN=\"com.github.ygini.Hello-IT\"\n"];
    [script appendString:@"LABEL=\"com.github.ygini.hello-it\"\n"];
    [script appendString:@"AGENT_PLIST=\"/Library/LaunchAgents/${LABEL}.plist\"\n"];
    [script appendString:@"COMPUTER_PLIST=\"/Library/Preferences/${DOMAIN}.plist\"\n"];
    [script appendString:@"APP=\"/Applications/Utilities/Hello IT.app\"\n"];
    [script appendString:@"TMP=\"$(mktemp -t hello-it-prefs).plist\"\n"];
    [script appendString:@"trap 'rm -f \"$TMP\"' EXIT\n\n"];
    [script appendFormat:@"cat > \"$TMP\" <<'%@'\n", marker];
    [script appendString:plistXML];
    if (![plistXML hasSuffix:@"\n"]) {
        [script appendString:@"\n"];
    }
    [script appendFormat:@"%@\n\n", marker];
    [script appendString:@"if [[ \"${EUID}\" -eq 0 ]]; then\n"];
    [script appendString:@"  # Avoid writing only to root's user domain (GUI users would never see it).\n"];
    [script appendString:@"  install -m 644 \"$TMP\" \"$COMPUTER_PLIST\"\n"];
    [script appendString:@"  echo \"Installed computer preferences: $COMPUTER_PLIST\"\n"];
    [script appendString:@"else\n"];
    [script appendString:@"  defaults import \"$DOMAIN\" \"$TMP\"\n"];
    [script appendString:@"  echo \"Imported Hello IT preferences into $DOMAIN for user $(id -un)\"\n"];
    [script appendString:@"fi\n\n"];
    // Reload only through launchd. open(1) + KeepAlive LaunchAgent is the dual-instance race
    // after pkg postinstall (agent already loaded) or when killall wait times out.
    [script appendString:@"hello_it_console_uids() {\n"];
    [script appendString:@"  ps aux | grep \"MacOS/[F]inder\" | awk '{print $1}' | while read -r shortname; do\n"];
    [script appendString:@"    id -u \"$shortname\" 2>/dev/null || true\n"];
    [script appendString:@"  done | sort -u\n"];
    [script appendString:@"}\n\n"];
    [script appendString:@"hello_it_kickstart_uid() {\n"];
    [script appendString:@"  local uid=\"$1\"\n"];
    [script appendString:@"  launchctl bootout \"gui/${uid}\" \"$AGENT_PLIST\" 2>/dev/null || true\n"];
    [script appendString:@"  launchctl bootstrap \"gui/${uid}\" \"$AGENT_PLIST\" 2>/dev/null || true\n"];
    [script appendString:@"  launchctl enable \"gui/${uid}/${LABEL}\" 2>/dev/null || true\n"];
    [script appendString:@"  launchctl kickstart -k \"gui/${uid}/${LABEL}\" 2>/dev/null || true\n"];
    [script appendString:@"}\n\n"];
    [script appendString:@"# Drop any stray instances (e.g. prior open(1)), then start exactly once via LaunchAgent.\n"];
    [script appendString:@"killall \"Hello IT\" 2>/dev/null || true\n"];
    [script appendString:@"sleep 0.2\n\n"];
    [script appendString:@"if [[ -f \"$AGENT_PLIST\" ]]; then\n"];
    [script appendString:@"  if [[ \"${EUID}\" -eq 0 ]]; then\n"];
    [script appendString:@"    uids=\"$(hello_it_console_uids)\"\n"];
    [script appendString:@"    if [[ -z \"${uids}\" ]]; then\n"];
    [script appendString:@"      echo \"Preferences saved; no GUI session to reload Hello IT into.\" >&2\n"];
    [script appendString:@"      exit 0\n"];
    [script appendString:@"    fi\n"];
    [script appendString:@"  else\n"];
    [script appendString:@"    uids=\"$(id -u)\"\n"];
    [script appendString:@"  fi\n"];
    [script appendString:@"  for uid in ${uids}; do\n"];
    [script appendString:@"    hello_it_kickstart_uid \"$uid\"\n"];
    [script appendString:@"  done\n"];
    [script appendString:@"  for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do\n"];
    [script appendString:@"    if pgrep -x \"Hello IT\" >/dev/null 2>&1; then\n"];
    [script appendString:@"      echo \"Hello IT reloaded.\"\n"];
    [script appendString:@"      exit 0\n"];
    [script appendString:@"    fi\n"];
    [script appendString:@"    sleep 0.25\n"];
    [script appendString:@"  done\n"];
    [script appendString:@"  echo \"Preferences saved; LaunchAgent did not start Hello IT in time.\" >&2\n"];
    [script appendString:@"  exit 0\n"];
    [script appendString:@"fi\n\n"];
    [script appendString:@"# No LaunchAgent (unusual / unpackaged install): open only if nothing is running.\n"];
    [script appendString:@"if [[ -d \"$APP\" ]]; then\n"];
    [script appendString:@"  if pgrep -x \"Hello IT\" >/dev/null 2>&1; then\n"];
    [script appendString:@"    echo \"Hello IT reloaded.\"\n"];
    [script appendString:@"  else\n"];
    [script appendString:@"    open \"$APP\"\n"];
    [script appendString:@"    echo \"Hello IT launched.\"\n"];
    [script appendString:@"  fi\n"];
    [script appendString:@"else\n"];
    [script appendString:@"  echo \"Preferences saved; Hello IT.app not found at $APP\" >&2\n"];
    [script appendString:@"fi\n"];

    return [script dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)writeExportData:(NSData *)data
                  toURL:(NSURL *)url
             executable:(BOOL)executable
                  error:(NSError **)error {
    if (!data || ![data writeToURL:url options:NSDataWritingAtomic error:error]) {
        return NO;
    }
    if (executable) {
        NSDictionary *attrs = @{ NSFilePosixPermissions: @0755 };
        [[NSFileManager defaultManager] setAttributes:attrs ofItemAtPath:url.path error:NULL];
    }
    return YES;
}

- (void)prepareForExport {
    [self.window makeFirstResponder:nil];
    [self commitInspectorToSelectedItem];
}

- (void)exportPlist:(id)sender {
    [self prepareForExport];

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[@"plist"];
    panel.nameFieldStringValue = @"com.github.ygini.Hello-IT.plist";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) {
            return;
        }
        NSError *error = nil;
        NSData *data = [self exportedPlistData:&error];
        if (![self writeExportData:data toURL:panel.URL executable:NO error:&error]) {
            [self presentError:error];
        }
    }];
}

- (void)exportMobileconfig:(id)sender {
    [self prepareForExport];

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[@"mobileconfig"];
    panel.nameFieldStringValue = @"HelloITConfiguration.mobileconfig";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) {
            return;
        }
        NSError *error = nil;
        NSData *data = [self exportedMobileconfigData:&error];
        if (![self writeExportData:data toURL:panel.URL executable:NO error:&error]) {
            [self presentError:error];
        }
    }];
}

- (void)exportBashScript:(id)sender {
    [self prepareForExport];

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedFileTypes = @[@"sh"];
    panel.nameFieldStringValue = @"install-hello-it-prefs.sh";
    panel.allowsOtherFileTypes = YES;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) {
            return;
        }
        NSError *error = nil;
        NSData *scriptData = [self exportedBashScriptData:&error];
        if (!scriptData) {
            [self presentError:error];
            return;
        }
        if (![self writeExportData:scriptData toURL:panel.URL executable:YES error:&error]) {
            [self presentError:error];
        }
    }];
}

- (NSString *)exportAllBaseNameFromURL:(NSURL *)url {
    NSString *name = url.lastPathComponent ?: @"HelloITConfiguration";
    NSString *ext = name.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"plist"] ||
        [ext isEqualToString:@"mobileconfig"] ||
        [ext isEqualToString:@"sh"] ||
        [ext isEqualToString:@"bash"]) {
        name = name.stringByDeletingPathExtension;
    }
    name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (name.length == 0) {
        name = @"HelloITConfiguration";
    }
    return name;
}

- (void)exportAll:(id)sender {
    [self prepareForExport];

    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.canCreateDirectories = YES;
    panel.allowsOtherFileTypes = YES;
    panel.extensionHidden = YES;
    panel.nameFieldLabel = @"Export As:";
    panel.nameFieldStringValue = @"HelloITConfiguration";
    panel.prompt = @"Export";
    panel.message = @"Writes three files with this name: .plist, .mobileconfig, and .sh";
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) {
            return;
        }
        NSURL *directory = [panel.URL URLByDeletingLastPathComponent];
        NSString *baseName = [self exportAllBaseNameFromURL:panel.URL];
        NSError *error = nil;

        NSData *plistData = [self exportedPlistData:&error];
        if (![self writeExportData:plistData
                             toURL:[directory URLByAppendingPathComponent:[baseName stringByAppendingPathExtension:@"plist"]]
                        executable:NO
                             error:&error]) {
            [self presentError:error];
            return;
        }

        NSData *profileData = [self exportedMobileconfigData:&error];
        if (![self writeExportData:profileData
                             toURL:[directory URLByAppendingPathComponent:[baseName stringByAppendingPathExtension:@"mobileconfig"]]
                        executable:NO
                             error:&error]) {
            [self presentError:error];
            return;
        }

        NSData *scriptData = [self exportedBashScriptData:&error];
        if (![self writeExportData:scriptData
                             toURL:[directory URLByAppendingPathComponent:[baseName stringByAppendingPathExtension:@"sh"]]
                        executable:YES
                             error:&error]) {
            [self presentError:error];
        }
    }];
}

- (void)importFile:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowedFileTypes = @[@"plist", @"mobileconfig"];
    panel.allowsMultipleSelection = NO;
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSModalResponse result) {
        if (result != NSModalResponseOK) {
            return;
        }
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfURL:panel.URL options:0 error:&error];
        if (!data) {
            [self presentError:error];
            return;
        }
        id plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:&error];
        if (!plist) {
            [self presentError:error];
            return;
        }

        NSDictionary *prefs = [self preferenceRootFromImportedPlist:plist];
        NSArray *content = nil;
        if ([prefs[kHITConfigSettings] isKindOfClass:[NSDictionary class]]) {
            content = prefs[kHITConfigSettings][kHITConfigContent];
        }
        if (![content isKindOfClass:[NSArray class]]) {
            content = prefs[kHITConfigContent];
        }
        if (![content isKindOfClass:[NSArray class]]) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = @"Could not find Hello IT menu content in that file.";
            [alert beginSheetModalForWindow:self.window completionHandler:nil];
            return;
        }

        self.rootContent = [self deepMutableCopyOfArray:content];
        self.selectedItem = nil;
        [self.outlineView reloadData];
        [self expandAllSubmenus];
    }];
}

- (NSDictionary *)preferenceRootFromImportedPlist:(id)plist {
    if (![plist isKindOfClass:[NSDictionary class]]) {
        return @{};
    }
    NSDictionary *dict = plist;

    // Raw preference plist
    if (dict[kHITConfigSettings] || dict[kHITConfigContent] || dict[kHITConfigFunctionIdentifier]) {
        return dict;
    }

    // mobileconfig → ManagedClient.preferences → Forced → mcx_preference_settings
    NSArray *payloadContent = dict[@"PayloadContent"];
    if (![payloadContent isKindOfClass:[NSArray class]]) {
        return @{};
    }
    for (NSDictionary *payload in payloadContent) {
        if (![payload isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        id nested = payload[@"PayloadContent"];
        if ([nested isKindOfClass:[NSDictionary class]]) {
            for (NSString *domain in @[@"com.github.ygini.Hello-IT", @"com.github.ygini.hello-it"]) {
                NSDictionary *domainPayload = nested[domain];
                NSArray *forced = domainPayload[@"Forced"];
                if ([forced isKindOfClass:[NSArray class]] && forced.count > 0) {
                    NSDictionary *settings = forced[0][@"mcx_preference_settings"];
                    if ([settings isKindOfClass:[NSDictionary class]]) {
                        return settings;
                    }
                }
            }
            // Direct preference payload style
            if (nested[kHITConfigSettings] || nested[kHITConfigContent]) {
                return nested;
            }
        }
    }
    return @{};
}

@end
