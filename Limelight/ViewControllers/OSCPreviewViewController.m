//
//  OSCPreviewViewController.m
//  Moonlight
//
//  See OSCPreviewViewController.h for usage.
//

#import "OSCPreviewViewController.h"
#import "ControllerSupport.h"
#import "StreamConfiguration.h"

#pragma mark - Offline ControllerSupport

// A ControllerSupport that never touches the streaming/network stack.
// OnScreenControls only sends input to the host inside -updateFinished:, so
// overriding it with a no-op makes the whole preview safe offline. All the
// state-mutating calls (setButtonFlag:, updateLeftStick:, ...) are kept as-is
// since they don't talk to the network and are needed for correctness.
@interface OSCPreviewControllerSupport : ControllerSupport
@end

@implementation OSCPreviewControllerSupport
- (void)updateFinished:(Controller *)controller {
    // Intentionally empty in preview mode.
}
- (void)sendKeyboardEvent:(short)keyCode down:(BOOL)down {
    // Intentionally empty in preview mode (don't touch the network stack).
}
@end

#pragma mark - Touch-forwarding container

@interface OSCPreviewContainerView : UIView
@property (nonatomic, weak) OnScreenControls *osc;
@end

@implementation OSCPreviewContainerView
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.osc handleTouchDownEvent:touches];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.osc handleTouchMovedEvent:touches];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.osc handleTouchUpEvent:touches];
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.osc handleTouchUpEvent:touches];
}
@end

#pragma mark - Preview view controller

@interface OSCPreviewViewController () <ControllerSupportDelegate>
@end

@implementation OSCPreviewViewController {
    OSCPreviewControllerSupport *_controllerSupport;
    OnScreenControls *_osc;
    OSCPreviewContainerView *_container;
    UISegmentedControl *_levelControl;
    CAGradientLayer *_gradientLayer;
    BOOL _built;
}

+ (void)presentFrom:(UIViewController *)presenter {
    OSCPreviewViewController *vc = [[OSCPreviewViewController alloc] init];
    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [presenter presentViewController:vc animated:YES completion:nil];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // Defaults
        _initialLevel = OnScreenControlsLevelKeyboard;
        _swapABXY = NO;
        _showsLevelSwitcher = NO; // keyboard-only preview
        _showsCloseButton = YES;
        _backdrop = OSCPreviewBackdropDarkGradient;
    }
    return self;
}

- (OnScreenControls *)onScreenControls {
    return _osc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    [self applyBackdrop];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    _gradientLayer.frame = self.view.bounds;

    if (_built) {
        return;
    }
    _built = YES;
    [self buildControls];
}

#pragma mark - Build

- (void)buildControls {
    StreamConfiguration *cfg = [[StreamConfiguration alloc] init];
    cfg.width = 1920;
    cfg.height = 1080;
    cfg.swapABXYButtons = _swapABXY;

    _controllerSupport = [[OSCPreviewControllerSupport alloc] initWithConfig:cfg delegate:self];

    _container = [[OSCPreviewContainerView alloc] initWithFrame:self.view.bounds];
    _container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _container.multipleTouchEnabled = YES;
    _container.backgroundColor = [UIColor clearColor];
    [self.view addSubview:_container];

    _osc = [[OnScreenControls alloc] initWithView:_container
                                     controllerSup:_controllerSupport
                                       streamConfig:cfg];
    _container.osc = _osc;
    [_osc setLevel:_initialLevel];
    [_osc show];

    if (_showsLevelSwitcher) {
        [self addLevelControl];
    }
    if (_showsCloseButton) {
        [self addCloseButton];
    }
}

#pragma mark - Backdrop

- (void)applyBackdrop {
    // Clean up any previous backdrop
    [_gradientLayer removeFromSuperlayer];
    _gradientLayer = nil;

    switch (_backdrop) {
        case OSCPreviewBackdropMidGray:
            self.view.backgroundColor = [UIColor colorWithWhite:0.35 alpha:1.0];
            break;
        case OSCPreviewBackdropCheckerboard:
            self.view.backgroundColor = [UIColor colorWithPatternImage:[self checkerboardImage]];
            break;
        case OSCPreviewBackdropDarkGradient:
        default: {
            self.view.backgroundColor = [UIColor blackColor];
            _gradientLayer = [CAGradientLayer layer];
            _gradientLayer.frame = self.view.bounds;
            _gradientLayer.colors = @[(id)[UIColor colorWithRed:0.10 green:0.13 blue:0.18 alpha:1.0].CGColor,
                                      (id)[UIColor colorWithRed:0.04 green:0.05 blue:0.08 alpha:1.0].CGColor];
            _gradientLayer.startPoint = CGPointMake(0, 0);
            _gradientLayer.endPoint = CGPointMake(1, 1);
            [self.view.layer insertSublayer:_gradientLayer atIndex:0];
            break;
        }
    }
}

- (UIImage *)checkerboardImage {
    CGFloat tile = 24.0;
    CGSize size = CGSizeMake(tile * 2, tile * 2);
    UIGraphicsBeginImageContextWithOptions(size, YES, 0);
    UIColor *c1 = [UIColor colorWithWhite:0.45 alpha:1.0];
    UIColor *c2 = [UIColor colorWithWhite:0.32 alpha:1.0];
    [c1 setFill];
    UIRectFill(CGRectMake(0, 0, size.width, size.height));
    [c2 setFill];
    UIRectFill(CGRectMake(0, 0, tile, tile));
    UIRectFill(CGRectMake(tile, tile, tile, tile));
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

#pragma mark - Chrome (overlay controls)

- (void)addLevelControl {
    _levelControl = [[UISegmentedControl alloc] initWithItems:@[@"Gamepad", @"Keyboard"]];
    _levelControl.selectedSegmentIndex = (_initialLevel == OnScreenControlsLevelKeyboard) ? 1 : 0;
    _levelControl.translatesAutoresizingMaskIntoConstraints = NO;
    [_levelControl addTarget:self action:@selector(levelChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:_levelControl];

    [NSLayoutConstraint activateConstraints:@[
        [_levelControl.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [_levelControl.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
    ]];
}

- (void)addCloseButton {
    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close setTitle:@"\u2715" forState:UIControlStateNormal]; // ✕
    close.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
    [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    close.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.18];
    close.layer.cornerRadius = 18;
    close.layer.borderWidth = 1.0;
    close.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.4].CGColor;
    [close addTarget:self action:@selector(closeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:close];

    [NSLayoutConstraint activateConstraints:@[
        [close.widthAnchor constraintEqualToConstant:36],
        [close.heightAnchor constraintEqualToConstant:36],
        [close.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor constant:16],
        [close.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
    ]];
}

- (void)levelChanged:(UISegmentedControl *)sender {
    OnScreenControlsLevel level = sender.selectedSegmentIndex == 0 ? OnScreenControlsLevelFull
                                                                   : OnScreenControlsLevelKeyboard;
    [_osc setLevel:level];
}

- (void)closeTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UIViewController overrides

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    // On-screen controls are designed for landscape
    return UIInterfaceOrientationMaskLandscape;
}

#pragma mark - ControllerSupportDelegate (no-ops for preview)

- (void)gamepadPresenceChanged {}
- (void)mousePresenceChanged {}
- (void)streamExitRequested {}

@end
