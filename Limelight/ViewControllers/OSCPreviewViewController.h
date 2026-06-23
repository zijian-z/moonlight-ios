//
//  OSCPreviewViewController.h
//  Moonlight
//
//  A standalone, reusable, OFFLINE preview of the on-screen controls
//  (virtual gamepad). It builds a real OnScreenControls instance on top of a
//  touch-forwarding container, but uses a ControllerSupport subclass that
//  never touches the network stack — so it can be shown anywhere, anytime,
//  without a streaming connection.
//
//  Reuse it to iterate on look & feel, button layout, skins, and (later) the
//  key-mapping editor.
//
//  Quick start — present from any view controller:
//      [OSCPreviewViewController presentFrom:self];
//
//  Or configure it first:
//      OSCPreviewViewController* vc = [[OSCPreviewViewController alloc] init];
//      vc.initialLevel = OnScreenControlsLevelFull;
//      vc.backdrop = OSCPreviewBackdropCheckerboard;
//      [self presentViewController:vc animated:YES completion:nil];
//

#import <UIKit/UIKit.h>
#import "OnScreenControls.h"

typedef NS_ENUM(NSInteger, OSCPreviewBackdrop) {
    OSCPreviewBackdropDarkGradient = 0, // Dark blue gradient (default)
    OSCPreviewBackdropMidGray,          // Flat mid gray
    OSCPreviewBackdropCheckerboard,     // Checkerboard, best for judging transparency
};

@class OnScreenControls;

@interface OSCPreviewViewController : UIViewController

#pragma mark - Configuration (set before the view loads)

/// On-screen controls level to show. Default: OnScreenControlsLevelFull.
@property (nonatomic) OnScreenControlsLevel initialLevel;

/// Whether to swap the A/B and X/Y button positions. Default: NO.
@property (nonatomic) BOOL swapABXY;

/// Show the Simple/Full segmented switcher at the top. Default: YES.
@property (nonatomic) BOOL showsLevelSwitcher;

/// Show a close button (dismisses the controller). Default: YES.
/// Set to NO when using this as a root view controller.
@property (nonatomic) BOOL showsCloseButton;

/// Backdrop style behind the controls. Default: OSCPreviewBackdropDarkGradient.
@property (nonatomic) OSCPreviewBackdrop backdrop;

#pragma mark - Access

/// The live OnScreenControls instance (available after the view has loaded).
@property (nonatomic, readonly, nullable) OnScreenControls *onScreenControls;

#pragma mark - Convenience

/// Modally present a full-screen preview from the given view controller.
+ (void)presentFrom:(nonnull UIViewController *)presenter;

@end
