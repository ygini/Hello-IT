//
//  HITConfiguratorController.h
//  Hello IT
//
//  SupportApp-style Configurator Mode (MVP): edit menu tree, apply locally, export profile.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface HITConfiguratorController : NSWindowController

+ (instancetype)sharedController;

/// Opens the configurator. Caller should reload the status menu after Apply.
@property (nonatomic, copy, nullable) void (^onApply)(void);

- (void)showConfigurator;

@end

NS_ASSUME_NONNULL_END
