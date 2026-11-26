//
//  HITPAbout.m
//  About
//

#import "HITPAbout.h"

@implementation HITPAbout

- (NSMenuItem *)prepareNewMenuItem {
    NSString *title = [self localizedString:[self.settings objectForKey:kHITSimplePluginTitleKey]];

    if ([title length] == 0) {
        title = [[NSBundle bundleForClass:[self class]] localizedStringForKey:@"ABOUT_SERVICE" value:@"About Hello IT" table:nil];
    }

    NSMenuItem *aboutItem = [[NSMenuItem alloc] initWithTitle:title
                                                       action:@selector(showAbout:)
                                                keyEquivalent:@""];
    aboutItem.target = self;
    return aboutItem;
}

- (void)showAbout:(id)sender {
    // LSUIElement apps need activation or the About panel stays behind other apps.
    [NSApp activateIgnoringOtherApps:YES];
    [NSApp orderFrontStandardAboutPanel:sender];
}

@end
