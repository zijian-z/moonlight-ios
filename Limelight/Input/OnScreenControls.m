//
//  OnScreenControls.m
//  Moonlight
//
//  Created by Diego Waxemberg on 12/28/14.
//  Copyright (c) 2014 Moonlight Stream. All rights reserved.
//

#import "OnScreenControls.h"
#import "StreamView.h"
#import "ControllerSupport.h"
#import "Controller.h"
#include "Limelight.h"

#import <UIKit/UIKit.h>

#define UPDATE_BUTTON(x, y) (buttonFlags = \
(y) ? (buttonFlags | (x)) : (buttonFlags & ~(x)))

// Left-stick -> arrow-key direction bits (keyboard mode)
#define SK_UP    0x1
#define SK_DOWN  0x2
#define SK_LEFT  0x4
#define SK_RIGHT 0x8

@implementation OnScreenControls {
    CALayer* _aButton;
    CALayer* _bButton;
    CALayer* _xButton;
    CALayer* _yButton;
    CALayer* _upButton;
    CALayer* _downButton;
    CALayer* _leftButton;
    CALayer* _rightButton;
    CALayer* _leftStickBackground;
    CALayer* _leftStick;
    CALayer* _rightStickBackground;
    CALayer* _rightStick;
    CALayer* _startButton;
    CALayer* _selectButton;
    CALayer* _r1Button;
    CALayer* _r2Button;
    CALayer* _r3Button;
    CALayer* _l1Button;
    CALayer* _l2Button;
    CALayer* _l3Button;
    
    UITouch* _aTouch;
    UITouch* _bTouch;
    UITouch* _xTouch;
    UITouch* _yTouch;
    UITouch* _dpadTouch;
    UITouch* _lsTouch;
    UITouch* _rsTouch;
    UITouch* _startTouch;
    UITouch* _selectTouch;
    UITouch* _r1Touch;
    UITouch* _r2Touch;
    UITouch* _r3Touch;
    UITouch* _l1Touch;
    UITouch* _l2Touch;
    UITouch* _l3Touch;
    
    NSDate* l3TouchStart;
    NSDate* r3TouchStart;
    
    BOOL l3Set;
    BOOL r3Set;
    
    BOOL _iPad;
    CGRect _controlArea;
    UIView* _view;
    OnScreenControlsLevel _level;
    BOOL _visible;
    
    ControllerSupport *_controllerSupport;
    Controller *_controller;
    NSMutableArray* _deadTouches;
    BOOL _swapABXY;

    // Modern look & feel.
    // Typed as id so the file still compiles on tvOS, where
    // UIImpactFeedbackGenerator is unavailable.
    id _hapticLight;
    id _hapticMedium;

    // Keyboard-mapped custom buttons (OnScreenControlsLevelKeyboard).
    NSMutableArray<CALayer*>* _keyButtons;   // button layers
    NSArray<NSString*>* _keyLabels;          // text shown on each button
    NSArray<NSNumber*>* _keyCodes;           // Win32 VK code for each button
    NSMutableArray* _keyTouches;             // UITouch* or NSNull per button
    int _stickKeyMask;                       // arrow keys currently held by the left stick

    // Frosted-glass backings keyed by their button layer.
    NSMapTable<CALayer*, UIVisualEffectView*>* _glassBackings;
}

static const float EDGE_WIDTH = .05;

// Spacing of face/d-pad buttons relative to their cluster center.
// Computed at init time from the (programmatically drawn) button sizes.
static float BUTTON_DIST;
static float BUTTON_CENTER_X;
static float BUTTON_CENTER_Y;

static float D_PAD_DIST;
static float D_PAD_CENTER_X;
static float D_PAD_CENTER_Y;

static const float DEAD_ZONE_PADDING = 15;

static const double STICK_CLICK_RATE = 100;
static const float STICK_DEAD_ZONE = .1;
static float STICK_INNER_SIZE;
static float STICK_OUTER_SIZE;
static float LS_CENTER_X;
static float LS_CENTER_Y;
static float RS_CENTER_X;
static float RS_CENTER_Y;

static float START_X;
static float START_Y;

static float SELECT_X;
static float SELECT_Y;

static float R1_X;
static float R1_Y;
static float R2_X;
static float R2_Y;
static float R3_X;
static float R3_Y;
static float L1_X;
static float L1_Y;
static float L2_X;
static float L2_Y;
static float L3_X;
static float L3_Y;

// Programmatic button dimensions (diameters / pill sizes)
static CGFloat OSC_ABXY_SIZE;
static CGFloat OSC_DPAD_SIZE;
static CGFloat OSC_STARTSELECT_SIZE;
static CGFloat OSC_BUMPER_W;
static CGFloat OSC_BUMPER_H;
static CGFloat OSC_TRIGGER_W;
static CGFloat OSC_TRIGGER_H;
static CGFloat OSC_L3R3_SIZE;
static CGFloat OSC_KEY_SIZE;          // keyboard-mapped buttons

// Visual style constants
static const CGFloat OSC_BASE_OPACITY      = 0.30f; // Resting opacity (keep gameplay visible)
static const CGFloat OSC_BORDER_WIDTH      = 1.0f;
static const NSTimeInterval OSC_ANIM_TIME  = 0.09;
static const CGFloat OSC_GLASS_REST_ALPHA  = 0.82f; // resting alpha of the frosted-glass backing

#pragma mark - Style helpers

+ (UIColor*) baseFillColor {
    return [UIColor colorWithWhite:1.0 alpha:0.14];
}

+ (UIColor*) baseStrokeColor {
    return [UIColor colorWithWhite:1.0 alpha:0.55];
}

+ (UIColor*) labelColor {
    return [UIColor colorWithWhite:1.0 alpha:0.92];
}

// Per-button accent colors used when pressed (classic gamepad mapping, modernized)
+ (UIColor*) accentGreen  { return [UIColor colorWithRed:0.30 green:0.82 blue:0.42 alpha:1.0]; }
+ (UIColor*) accentRed    { return [UIColor colorWithRed:0.95 green:0.36 blue:0.36 alpha:1.0]; }
+ (UIColor*) accentBlue   { return [UIColor colorWithRed:0.30 green:0.62 blue:0.98 alpha:1.0]; }
+ (UIColor*) accentYellow { return [UIColor colorWithRed:0.98 green:0.78 blue:0.27 alpha:1.0]; }
+ (UIColor*) accentCyan   { return [UIColor colorWithRed:0.25 green:0.80 blue:0.92 alpha:1.0]; }
+ (UIColor*) accentNeutral{ return [UIColor colorWithWhite:1.0 alpha:0.85]; }

// Configure a CALayer to look like a modern, semi-transparent on-screen button.
- (void) styleButton:(CALayer*)layer
               label:(NSString*)label
              accent:(UIColor*)accent
            cornerR:(CGFloat)cornerRadius
           fontSize:(CGFloat)fontSize {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];

    layer.backgroundColor = [OnScreenControls baseFillColor].CGColor;
    layer.borderColor = [OnScreenControls baseStrokeColor].CGColor;
    layer.borderWidth = OSC_BORDER_WIDTH;
    layer.cornerRadius = cornerRadius;
    layer.contents = nil;

    // Rest semi-transparent so the controls don't obscure gameplay;
    // they light up to full opacity when pressed.
    layer.opacity = OSC_BASE_OPACITY;

    // Subtle drop shadow for legibility against bright gameplay
    layer.shadowColor = [UIColor blackColor].CGColor;
    layer.shadowOffset = CGSizeMake(0, 1);
    layer.shadowRadius = 3.0f;
    layer.shadowOpacity = 0.22f;

    // Store the accent so press handlers can highlight consistently
    [layer setValue:accent forKey:@"oscAccent"];

    // (Re)build the text label
    [self setLabel:label onLayer:layer fontSize:fontSize];

    [CATransaction commit];
}

#pragma mark - Frosted glass backing

// Same as styleButton, but adds an iOS frosted-glass (UIVisualEffectView)
// backing beneath the button and makes the layer background transparent so the
// blur shows through. The layer still owns the border, label and hit testing.
- (void) styleGlassButton:(CALayer*)layer
                    label:(NSString*)label
                   accent:(UIColor*)accent
                  cornerR:(CGFloat)cornerRadius
                 fontSize:(CGFloat)fontSize {
    [self styleButton:layer label:label accent:accent cornerR:cornerRadius fontSize:fontSize];

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.backgroundColor = [UIColor clearColor].CGColor; // let the blur show
    layer.opacity = 1.0f;                                 // border/label stay crisp
    [CATransaction commit];

    [self attachGlassToLayer:layer cornerRadius:cornerRadius];
}

- (void) attachGlassToLayer:(CALayer*)layer cornerRadius:(CGFloat)r {
    UIVisualEffectView* glass = [_glassBackings objectForKey:layer];
    if (glass == nil) {
        UIBlurEffect* effect;
        if (@available(iOS 13.0, tvOS 13.0, *)) {
            effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterialDark];
        } else {
            effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
        }
        glass = [[UIVisualEffectView alloc] initWithEffect:effect];
        glass.userInteractionEnabled = NO;
        glass.clipsToBounds = YES;
        [_glassBackings setObject:glass forKey:layer];
    }
    glass.transform = CGAffineTransformIdentity;
    glass.frame = layer.frame;
    glass.layer.cornerRadius = r;
    glass.alpha = OSC_GLASS_REST_ALPHA;
    // Add on top of any video; the button layer is added afterwards so it
    // stays above this glass view.
    [_view addSubview:glass];
}

- (void) detachGlassFromLayer:(CALayer*)layer {
    UIVisualEffectView* glass = [_glassBackings objectForKey:layer];
    [glass removeFromSuperview];
}

- (void) setLabel:(NSString*)label onLayer:(CALayer*)layer fontSize:(CGFloat)fontSize {
    // Remove any previous label sublayers
    NSMutableArray* survivors = [NSMutableArray array];
    for (CALayer* sub in layer.sublayers) {
        if (![sub.name isEqualToString:@"oscLabel"]) {
            [survivors addObject:sub];
        }
    }
    layer.sublayers = survivors.count ? survivors : nil;

    if (label.length == 0) {
        return;
    }

    CATextLayer* text = [CATextLayer layer];
    text.name = @"oscLabel";
    text.string = label;
    text.font = (__bridge CFTypeRef)[UIFont systemFontOfSize:fontSize weight:UIFontWeightSemibold].fontName;
    text.fontSize = fontSize;
    text.foregroundColor = [OnScreenControls labelColor].CGColor;
    text.alignmentMode = kCAAlignmentCenter;
    text.contentsScale = [UIScreen mainScreen].scale;
    // Vertically center the (single-line) text
    CGFloat h = fontSize * 1.25f;
    text.frame = CGRectMake(0, (layer.bounds.size.height - h) / 2.0f, layer.bounds.size.width, h);
    [layer addSublayer:text];
}

// Animate a button between resting and pressed states.
- (void) setButton:(CALayer*)layer pressed:(BOOL)pressed {
    UIColor* accent = [layer valueForKey:@"oscAccent"];
    if (accent == nil) {
        accent = [OnScreenControls accentNeutral];
    }

    UIVisualEffectView* glass = [_glassBackings objectForKey:layer];

    [CATransaction begin];
    [CATransaction setAnimationDuration:OSC_ANIM_TIME];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];

    if (pressed) {
        layer.backgroundColor = [accent colorWithAlphaComponent:0.55].CGColor;
        layer.borderColor = accent.CGColor;
        layer.borderWidth = OSC_BORDER_WIDTH + 0.5f;
        layer.transform = CATransform3DMakeScale(0.90f, 0.90f, 1.0f);
        layer.shadowOpacity = 0.15f;
        layer.opacity = 1.0f;
    } else {
        // Glass-backed buttons stay transparent so the blur shows through.
        layer.backgroundColor = glass ? [UIColor clearColor].CGColor : [OnScreenControls baseFillColor].CGColor;
        layer.borderColor = [OnScreenControls baseStrokeColor].CGColor;
        layer.borderWidth = OSC_BORDER_WIDTH;
        layer.transform = CATransform3DIdentity;
        layer.shadowOpacity = 0.35f;
        layer.opacity = glass ? 1.0f : OSC_BASE_OPACITY;
    }

    [CATransaction commit];

    // Keep the glass backing in sync with the button's press animation.
    if (glass != nil) {
        [UIView animateWithDuration:OSC_ANIM_TIME delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            glass.transform = pressed ? CGAffineTransformMakeScale(0.90f, 0.90f) : CGAffineTransformIdentity;
            glass.alpha = pressed ? 1.0f : OSC_GLASS_REST_ALPHA;
        } completion:nil];
    }
}

- (void) playHaptic:(id)generator {
#if !TARGET_OS_TV
    if (generator != nil) {
        UIImpactFeedbackGenerator* g = (UIImpactFeedbackGenerator*)generator;
        [g impactOccurred];
        [g prepare];
    }
#endif
}

- (id) initWithView:(UIView*)view controllerSup:(ControllerSupport*)controllerSupport streamConfig:(StreamConfiguration*)streamConfig {
    self = [self init];
    _view = view;
    _controllerSupport = controllerSupport;
    _controller = [controllerSupport getOscController];
    _deadTouches = [[NSMutableArray alloc] init];
    _swapABXY = streamConfig.swapABXYButtons;
    
    _iPad = ([UIDevice currentDevice].userInterfaceIdiom == UIUserInterfaceIdiomPad);
    _controlArea = CGRectMake(0, 0, _view.frame.size.width, _view.frame.size.height);
    if (_iPad)
    {
        // Cut down the control area on an iPad so the controls are more reachable
        _controlArea.size.height = _view.frame.size.height / 2.0;
        _controlArea.origin.y = _view.frame.size.height - _controlArea.size.height;
    }
    else
    {
        _controlArea.origin.x = _controlArea.size.width * EDGE_WIDTH;
        _controlArea.size.width -= _controlArea.origin.x * 2;
    }

    // Size the controls relative to the device. Larger, finger-friendly
    // targets like modern mobile games rather than tiny fixed sprites.
    CGFloat scale = _iPad ? 1.25f : 1.0f;
    OSC_ABXY_SIZE        = 50.f * scale;
    OSC_DPAD_SIZE        = 42.f * scale;
    OSC_STARTSELECT_SIZE = 36.f * scale;
    OSC_BUMPER_W         = 66.f * scale;
    OSC_BUMPER_H         = 34.f * scale;
    OSC_TRIGGER_W        = 66.f * scale;
    OSC_TRIGGER_H        = 34.f * scale;
    OSC_L3R3_SIZE        = 48.f * scale;
    OSC_KEY_SIZE         = 44.f * scale;
    STICK_OUTER_SIZE     = 112.f * scale;
    STICK_INNER_SIZE     = 48.f * scale;

    // Cluster spacing so the four face buttons / d-pad arrows sit snugly around
    // their center without overlapping.
    BUTTON_DIST = OSC_ABXY_SIZE * 0.62f;
    D_PAD_DIST  = OSC_DPAD_SIZE * 0.55f;

    _aButton = [CALayer layer];
    _bButton = [CALayer layer];
    _xButton = [CALayer layer];
    _yButton = [CALayer layer];
    _upButton = [CALayer layer];
    _downButton = [CALayer layer];
    _leftButton = [CALayer layer];
    _rightButton = [CALayer layer];
    _l1Button = [CALayer layer];
    _r1Button = [CALayer layer];
    _l2Button = [CALayer layer];
    _r2Button = [CALayer layer];
    _l3Button = [CALayer layer];
    _r3Button = [CALayer layer];
    _startButton = [CALayer layer];
    _selectButton = [CALayer layer];
    _leftStickBackground = [CALayer layer];
    _rightStickBackground = [CALayer layer];
    _leftStick = [CALayer layer];
    _rightStick = [CALayer layer];

    // Genshin-style layout:
    //   index 0      -> big "attack" button (X)
    //   index 1..8   -> small skill keys Q W E R / A S D F arced around it
    //   index 9..11  -> function keys ESC, Enter, Space (top-right)
    // Values are Win32 Virtual Key codes interpreted on a US English layout.
    _keyLabels = @[@"\U0001F5E1\U0000FE0F", // attack button shows a dagger/sword emoji 🗡️
                   @"Q", @"W", @"E", @"R", @"A", @"S", @"D", @"F",
                   @"ESC", @"\u21B5", @"\u2423"]; // ESC, Enter (↵), Space (␣)
    _keyCodes  = @[@0x58,
                   @0x51, @0x57, @0x45, @0x52, @0x41, @0x53, @0x44, @0x46,
                   @0x1B, @0x0D, @0x20];          // VK_ESCAPE, VK_RETURN, VK_SPACE
    _keyButtons = [[NSMutableArray alloc] init];
    _keyTouches = [[NSMutableArray alloc] init];
    _glassBackings = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory | NSPointerFunctionsObjectPointerPersonality
                                           valueOptions:NSPointerFunctionsStrongMemory];
    for (NSUInteger i = 0; i < _keyLabels.count; i++) {
        [_keyButtons addObject:[CALayer layer]];
        [_keyTouches addObject:[NSNull null]];
    }

    // Haptic feedback generators (kept "primed" for low latency).
    // Not available on tvOS.
#if !TARGET_OS_TV
    _hapticLight = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    _hapticMedium = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [(UIImpactFeedbackGenerator*)_hapticLight prepare];
    [(UIImpactFeedbackGenerator*)_hapticMedium prepare];
#endif

    return self;
}

- (void) show {
    _visible = YES;
        
    [self updateControls];
}

- (void) setLevel:(OnScreenControlsLevel)level {
    _level = level;
    
    // Only update controls if we're showing, otherwise
    // show will do it for us.
    if (_visible) {
        [self updateControls];
    }
}

- (OnScreenControlsLevel) getLevel {
    return _level;
}

- (void) updateControls {
    // Always clear keyboard buttons first; the keyboard case re-adds them.
    [self hideKeyboardButtons];

    switch (_level) {
        case OnScreenControlsLevelKeyboard:
            [self setupKeyboardControls];

            [self hideButtons];
            [self hideBumpers];
            [self hideTriggers];
            [self hideStartSelect];
            [self hideL3R3];
            [self hideSticks];     // remove both sticks...
            [self drawLeftStickOnly]; // ...then show only the left one
            [self drawKeyboardButtons];
            break;
        case OnScreenControlsLevelOff:
            [self hideButtons];
            [self hideBumpers];
            [self hideTriggers];
            [self hideStartSelect];
            [self hideSticks];
            [self hideL3R3];
            break;
        case OnScreenControlsLevelAutoGCGamepad:
            // GCGamepad is missing triggers, both analog sticks,
            // and the select button
            [self setupGamepadControls];
            
            [self hideButtons];
            [self hideBumpers];
            [self hideL3R3];
            [self drawTriggers];
            [self drawStartSelect];
            [self drawSticks];
            break;
        case OnScreenControlsLevelAutoGCExtendedGamepad:
            // GCExtendedGamepad is missing R3, L3, and select
            [self setupExtendedGamepadControls];
            
            [self hideButtons];
            [self hideBumpers];
            [self hideTriggers];
            [self drawStartSelect];
            [self hideSticks];
            [self drawL3R3];
            break;
        case OnScreenControlsLevelAutoGCExtendedGamepadWithStickButtons:
            // This variant of GCExtendedGamepad has L3 and R3 but
            // is still missing Select
            [self setupExtendedGamepadControls];
            
            [self hideButtons];
            [self hideBumpers];
            [self hideTriggers];
            [self hideL3R3];
            [self drawStartSelect];
            [self hideSticks];
            break;
        case OnScreenControlsLevelSimple:
            [self setupSimpleControls];
            
            [self hideTriggers];
            [self hideL3R3];
            [self hideBumpers];
            [self hideSticks];
            [self drawStartSelect];
            [self drawButtons];
            break;
        case OnScreenControlsLevelFull:
            [self setupComplexControls];
            
            [self drawButtons];
            [self drawStartSelect];
            [self drawBumpers];
            [self drawTriggers];
            [self drawSticks];
            [self hideL3R3]; // Full controls don't need these they have the sticks
            break;
        default:
            Log(LOG_W, @"Unknown on-screen controls level: %d", (int)_level);
            break;
    }
}

// For GCExtendedGamepad controls we move start, select, L3, and R3 to the button
- (void) setupExtendedGamepadControls {
    // Start with the default complex layout
    [self setupComplexControls];
    
    START_X = _controlArea.size.width * .95 + _controlArea.origin.x;
    START_Y = _controlArea.size.height * .9 + _controlArea.origin.y;
    SELECT_X = _controlArea.size.width * .05 + _controlArea.origin.x;
    SELECT_Y = _controlArea.size.height * .9 + _controlArea.origin.y;
    
    L3_Y = _controlArea.size.height * .85 + _controlArea.origin.y;
    R3_Y = _controlArea.size.height * .85 + _controlArea.origin.y;
    
    if (_iPad) {
        L3_X = _controlArea.size.width * .15 + _controlArea.origin.x;
        R3_X = _controlArea.size.width * .85 + _controlArea.origin.x;
    }
    else {
        L3_X = _controlArea.size.width * .25 + _controlArea.origin.x;
        R3_X = _controlArea.size.width * .75 + _controlArea.origin.x;
    }
}

// For GCGamepad controls we move triggers, start, and select
// to sit right above the analog sticks
- (void) setupGamepadControls {
    // Start with the default complex layout
    [self setupComplexControls];
    
    L2_Y = _controlArea.size.height * .75 + _controlArea.origin.y;
    L2_X = _controlArea.size.width * .05 + _controlArea.origin.x;
    
    R2_Y = _controlArea.size.height * .75 + _controlArea.origin.y;
    R2_X = _controlArea.size.width * .95 + _controlArea.origin.x;
    
    START_X = _controlArea.size.width * .95 + _controlArea.origin.x;
    START_Y = _controlArea.size.height * .95 + _controlArea.origin.y;
    SELECT_X = _controlArea.size.width * .05 + _controlArea.origin.x;
    SELECT_Y = _controlArea.size.height * .95 + _controlArea.origin.y;
    
    if (_iPad) {
        // The analog sticks are kept closer to the sides on iPad
        LS_CENTER_X = _controlArea.size.width * .15 + _controlArea.origin.x;
        RS_CENTER_X = _controlArea.size.width * .85 + _controlArea.origin.x;
    }
}

// For simple controls we move the triggers and buttons to the bottom
- (void) setupSimpleControls {
    // Start with the default complex layout
    [self setupComplexControls];
    
    START_Y = _controlArea.size.height * .9 + _controlArea.origin.y;
    SELECT_Y = _controlArea.size.height * .9 + _controlArea.origin.y;
    
    L2_Y = _controlArea.size.height * .9 + _controlArea.origin.y;
    L2_X = _controlArea.size.width * .1 + _controlArea.origin.x;

    R2_Y = _controlArea.size.height * .9 + _controlArea.origin.y;
    R2_X = _controlArea.size.width * .9 + _controlArea.origin.x;
    
    if (_iPad) {
        // Lower the D-pad and buttons on iPad
        D_PAD_CENTER_Y = _controlArea.size.height * .75 + _controlArea.origin.y;
        BUTTON_CENTER_Y = _controlArea.size.height * .75 + _controlArea.origin.y;
        
        // Move Start and Select closer to sides
        SELECT_X = _controlArea.size.width * .2 + _controlArea.origin.x;
        START_X = _controlArea.size.width * .8 + _controlArea.origin.x;
    }
    else {
        SELECT_X = _controlArea.size.width * .4 + _controlArea.origin.x;
        START_X = _controlArea.size.width * .6 + _controlArea.origin.x;
    }
}

- (void) setupComplexControls
{
    D_PAD_CENTER_X = _controlArea.size.width * .1 + _controlArea.origin.x;
    D_PAD_CENTER_Y = _controlArea.size.height * .60 + _controlArea.origin.y;
    BUTTON_CENTER_X = _controlArea.size.width * .9 + _controlArea.origin.x;
    BUTTON_CENTER_Y = _controlArea.size.height * .60 + _controlArea.origin.y;
    
    if (_iPad)
    {
        // The analog sticks are kept closer to the sides on iPad
        LS_CENTER_X = _controlArea.size.width * .22 + _controlArea.origin.x;
        LS_CENTER_Y = _controlArea.size.height * .80 + _controlArea.origin.y;
        RS_CENTER_X = _controlArea.size.width * .77 + _controlArea.origin.x;
        RS_CENTER_Y = _controlArea.size.height * .80 + _controlArea.origin.y;
    }
    else
    {
        LS_CENTER_X = _controlArea.size.width * .35 + _controlArea.origin.x;
        LS_CENTER_Y = _controlArea.size.height * .75 + _controlArea.origin.y;
        RS_CENTER_X = _controlArea.size.width * .65 + _controlArea.origin.x;
        RS_CENTER_Y = _controlArea.size.height * .75 + _controlArea.origin.y;
    }
    
    START_X = _controlArea.size.width * .9 + _controlArea.origin.x;
    START_Y = _controlArea.size.height * .9 + _controlArea.origin.y;
    SELECT_X = _controlArea.size.width * .1 + _controlArea.origin.x;
    SELECT_Y = _controlArea.size.height * .9 + _controlArea.origin.y;
    
    L1_Y = _controlArea.size.height * .27 + _controlArea.origin.y;
    L2_Y = _controlArea.size.height * .1 + _controlArea.origin.y;
    R1_Y = _controlArea.size.height * .27 + _controlArea.origin.y;
    R2_Y = _controlArea.size.height * .1 + _controlArea.origin.y;
    
    if (_iPad) {
        // Move L/R buttons closer to the side on iPad
        L1_X = _controlArea.size.width * .05 + _controlArea.origin.x;
        L2_X = _controlArea.size.width * .05 + _controlArea.origin.x;
        R1_X = _controlArea.size.width * .95 + _controlArea.origin.x;
        R2_X = _controlArea.size.width * .95 + _controlArea.origin.x;
    }
    else {
        L1_X = _controlArea.size.width * .1 + _controlArea.origin.x;
        L2_X = _controlArea.size.width * .1 + _controlArea.origin.x;
        R1_X = _controlArea.size.width * .9 + _controlArea.origin.x;
        R2_X = _controlArea.size.width * .9 + _controlArea.origin.x;
    }
}

// Keyboard mode: a single left stick on the left, key grid on the right.
- (void) setupKeyboardControls {
    LS_CENTER_X = _controlArea.origin.x + _controlArea.size.width * (_iPad ? 0.15f : 0.16f);
    LS_CENTER_Y = _controlArea.origin.y + _controlArea.size.height * 0.74f;
}

#pragma mark - Drawing (programmatic, modern style)

- (CGRect) roundFrameAt:(CGPoint)center size:(CGFloat)size {
    return CGRectMake(center.x - size / 2.0f, center.y - size / 2.0f, size, size);
}

// Draws only the left analog stick (used by keyboard mode).
- (void) drawLeftStickOnly {
    _leftStickBackground.frame = [self roundFrameAt:CGPointMake(LS_CENTER_X, LS_CENTER_Y) size:STICK_OUTER_SIZE];
    [self styleStickBackground:_leftStickBackground];
    // Frosted-glass base; the (moving) thumb stays a solid layer.
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _leftStickBackground.backgroundColor = [UIColor clearColor].CGColor;
    _leftStickBackground.opacity = 1.0f;
    [CATransaction commit];
    [self attachGlassToLayer:_leftStickBackground cornerRadius:STICK_OUTER_SIZE / 2.0f];
    [_view.layer addSublayer:_leftStickBackground];

    _leftStick.frame = [self roundFrameAt:CGPointMake(LS_CENTER_X, LS_CENTER_Y) size:STICK_INNER_SIZE];
    [self styleStickThumb:_leftStick];
    [_view.layer addSublayer:_leftStick];
}

// Draws the right-side grid of keyboard-mapped buttons (2 rows x 4 cols).
// Genshin-inspired layout: a large attack button in the lower-right, with the
// smaller skill keys arced around its upper side, and function keys top-right.
// Layout (per user's design): the skill keys form a full ring around the
// attack button — A S D F on the LEFT half, Q W E R on the RIGHT half.
//   X (attack)          -> center of the ring, lower-right of the screen.
//   Q W E R             -> right half of the ring (top-right -> right -> bottom-right).
//   A S D F             -> left half of the ring (top-left -> left -> bottom-left).
//   ESC / Enter / Space -> a small row at the top-right.
- (void) drawKeyboardButtons {
    CGFloat s = OSC_KEY_SIZE;                 // small key diameter
    CGFloat attack = OSC_KEY_SIZE * 1.7f;     // attack button at the ring center

    CGFloat right  = _controlArea.origin.x + _controlArea.size.width;
    CGFloat top    = _controlArea.origin.y;
    CGFloat bottom = _controlArea.origin.y + _controlArea.size.height;

    // Radius of the ring the small keys sit on.
    CGFloat R = attack / 2.0f + s * 0.72f + 14.0f;

    // Attack button center: lower-right, with enough room for the full ring.
    CGFloat ax = right - R - s / 2.0f - 10.0f;
    CGFloat ay = bottom - R - s / 2.0f - 10.0f;
    if (ay - R - s / 2.0f < top + 8.0f) {
        ay = top + R + s / 2.0f + 8.0f;
    }

    // index 0: attack button
    [self placeKeyButtonAtIndex:0 center:CGPointMake(ax, ay) size:attack
                         accent:[OnScreenControls accentRed]];

    // Q W E R (index 1..4): right half of the ring.
    // Spread across the right side: top-right -> right -> bottom-right.
    // (300° -> 420° sweeps through 360° = straight right.)
    NSUInteger rightHalf = MIN((NSUInteger)4, _keyButtons.count > 1 ? _keyButtons.count - 1 : 0);
    [self placeArcKeysStartIndex:1 count:rightHalf centerX:ax centerY:ay radius:R
                        startDeg:300.0f endDeg:420.0f accent:[OnScreenControls accentBlue]];

    // A S D F (index 5..8): left half of the ring.
    // Spread across the left side: bottom-left -> left -> top-left.
    NSUInteger leftHalf = MIN((NSUInteger)4, _keyButtons.count > 5 ? _keyButtons.count - 5 : 0);
    [self placeArcKeysStartIndex:5 count:leftHalf centerX:ax centerY:ay radius:R
                        startDeg:120.0f endDeg:240.0f accent:[OnScreenControls accentBlue]];

    // ESC / Enter / Space (index 9..11): small row at the top-right.
    NSUInteger fnStart = 9;
    CGFloat fy = top + s / 2.0f + 10.0f;
    CGFloat fx = right - s / 2.0f - 8.0f;
    for (NSUInteger j = 0; fnStart + j < _keyButtons.count; j++) {
        [self placeKeyButtonAtIndex:(fnStart + j)
                             center:CGPointMake(fx - j * (s + 10.0f), fy)
                               size:s
                             accent:[OnScreenControls accentNeutral]];
    }
}

// Places `count` keys (starting at `startIndex`) evenly along an arc.
- (void) placeArcKeysStartIndex:(NSUInteger)startIndex
                          count:(NSUInteger)count
                        centerX:(CGFloat)cx
                        centerY:(CGFloat)cy
                         radius:(CGFloat)R
                       startDeg:(CGFloat)startDeg
                         endDeg:(CGFloat)endDeg
                         accent:(UIColor*)accent {
    for (NSUInteger k = 0; k < count; k++) {
        CGFloat t = (count <= 1) ? 0.0f : (CGFloat)k / (CGFloat)(count - 1);
        CGFloat deg = startDeg + t * (endDeg - startDeg);
        CGFloat rad = deg * (CGFloat)M_PI / 180.0f;
        CGFloat kx = cx + R * cosf(rad);
        CGFloat ky = cy + R * sinf(rad); // screen y is down
        [self placeKeyButtonAtIndex:(startIndex + k)
                             center:CGPointMake(kx, ky)
                               size:OSC_KEY_SIZE
                             accent:accent];
    }
}

// Positions, styles and shows a single keyboard button.
- (void) placeKeyButtonAtIndex:(NSUInteger)i center:(CGPoint)c size:(CGFloat)d accent:(UIColor*)accent {
    if (i >= _keyButtons.count) {
        return;
    }
    CALayer* btn = _keyButtons[i];
    btn.frame = [self roundFrameAt:c size:d];
    NSString* label = (i < _keyLabels.count) ? _keyLabels[i] : @"";
    // Pick a font/icon size. The attack button is index 0 (an emoji icon) and
    // gets a larger glyph; multi-character text labels (e.g. "ESC") render
    // smaller; single characters use the default size.
    CGFloat fs;
    if (i == 0) {
        fs = d * 0.50f;
    } else if (label.length > 1) {
        fs = d * 0.30f;
    } else {
        fs = d * 0.42f;
    }
    [self styleGlassButton:btn label:label accent:accent cornerR:d / 2.0f fontSize:fs];
    [_view.layer addSublayer:btn];
}

- (void) hideKeyboardButtons {
    for (CALayer* btn in _keyButtons) {
        [btn removeFromSuperlayer];
        [self detachGlassFromLayer:btn];
    }
}

- (void) drawButtons {
    CGFloat r = OSC_ABXY_SIZE;
    CGFloat fs = OSC_ABXY_SIZE * 0.42f;

    // A is below center, B to the right, X to the left, Y above center
    CGRect aButtonFrame = CGRectMake(BUTTON_CENTER_X - r / 2, BUTTON_CENTER_Y + BUTTON_DIST - r / 2, r, r);
    CGRect bButtonFrame = CGRectMake(BUTTON_CENTER_X + BUTTON_DIST - r / 2, BUTTON_CENTER_Y - r / 2, r, r);
    CGRect xButtonFrame = CGRectMake(BUTTON_CENTER_X - BUTTON_DIST - r / 2, BUTTON_CENTER_Y - r / 2, r, r);
    CGRect yButtonFrame = CGRectMake(BUTTON_CENTER_X - r / 2, BUTTON_CENTER_Y - BUTTON_DIST - r / 2, r, r);

    _aButton.frame = _swapABXY ? bButtonFrame : aButtonFrame;
    [self styleButton:_aButton label:@"A" accent:[OnScreenControls accentGreen] cornerR:r / 2 fontSize:fs];
    [_view.layer addSublayer:_aButton];

    _bButton.frame = _swapABXY ? aButtonFrame : bButtonFrame;
    [self styleButton:_bButton label:@"B" accent:[OnScreenControls accentRed] cornerR:r / 2 fontSize:fs];
    [_view.layer addSublayer:_bButton];

    _xButton.frame = _swapABXY ? yButtonFrame : xButtonFrame;
    [self styleButton:_xButton label:@"X" accent:[OnScreenControls accentBlue] cornerR:r / 2 fontSize:fs];
    [_view.layer addSublayer:_xButton];

    _yButton.frame = _swapABXY ? xButtonFrame : yButtonFrame;
    [self styleButton:_yButton label:@"Y" accent:[OnScreenControls accentYellow] cornerR:r / 2 fontSize:fs];
    [_view.layer addSublayer:_yButton];

    // D-pad
    CGFloat d = OSC_DPAD_SIZE;
    CGFloat dfs = OSC_DPAD_SIZE * 0.46f;
    UIColor* dpadAccent = [OnScreenControls accentCyan];

    _downButton.frame = CGRectMake(D_PAD_CENTER_X - d / 2, D_PAD_CENTER_Y + D_PAD_DIST - d / 2, d, d);
    [self styleButton:_downButton label:@"\u25BC" accent:dpadAccent cornerR:d * 0.28f fontSize:dfs];
    [_view.layer addSublayer:_downButton];

    _rightButton.frame = CGRectMake(D_PAD_CENTER_X + D_PAD_DIST - d / 2, D_PAD_CENTER_Y - d / 2, d, d);
    [self styleButton:_rightButton label:@"\u25B6" accent:dpadAccent cornerR:d * 0.28f fontSize:dfs];
    [_view.layer addSublayer:_rightButton];

    _upButton.frame = CGRectMake(D_PAD_CENTER_X - d / 2, D_PAD_CENTER_Y - D_PAD_DIST - d / 2, d, d);
    [self styleButton:_upButton label:@"\u25B2" accent:dpadAccent cornerR:d * 0.28f fontSize:dfs];
    [_view.layer addSublayer:_upButton];

    _leftButton.frame = CGRectMake(D_PAD_CENTER_X - D_PAD_DIST - d / 2, D_PAD_CENTER_Y - d / 2, d, d);
    [self styleButton:_leftButton label:@"\u25C0" accent:dpadAccent cornerR:d * 0.28f fontSize:dfs];
    [_view.layer addSublayer:_leftButton];
}

- (void) drawStartSelect {
    CGFloat s = OSC_STARTSELECT_SIZE;
    CGFloat fs = OSC_STARTSELECT_SIZE * 0.40f;

    _startButton.frame = [self roundFrameAt:CGPointMake(START_X, START_Y) size:s];
    [self styleButton:_startButton label:@"\u2630" accent:[OnScreenControls accentNeutral] cornerR:s / 2 fontSize:fs];
    [_view.layer addSublayer:_startButton];

    _selectButton.frame = [self roundFrameAt:CGPointMake(SELECT_X, SELECT_Y) size:s];
    [self styleButton:_selectButton label:@"\u2750" accent:[OnScreenControls accentNeutral] cornerR:s / 2 fontSize:fs];
    [_view.layer addSublayer:_selectButton];
}

- (void) drawBumpers {
    CGFloat fs = OSC_BUMPER_H * 0.40f;

    _l1Button.frame = CGRectMake(L1_X - OSC_BUMPER_W / 2, L1_Y - OSC_BUMPER_H / 2, OSC_BUMPER_W, OSC_BUMPER_H);
    [self styleButton:_l1Button label:@"LB" accent:[OnScreenControls accentNeutral] cornerR:OSC_BUMPER_H / 2 fontSize:fs];
    [_view.layer addSublayer:_l1Button];

    _r1Button.frame = CGRectMake(R1_X - OSC_BUMPER_W / 2, R1_Y - OSC_BUMPER_H / 2, OSC_BUMPER_W, OSC_BUMPER_H);
    [self styleButton:_r1Button label:@"RB" accent:[OnScreenControls accentNeutral] cornerR:OSC_BUMPER_H / 2 fontSize:fs];
    [_view.layer addSublayer:_r1Button];
}

- (void) drawTriggers {
    CGFloat fs = OSC_TRIGGER_H * 0.40f;

    _l2Button.frame = CGRectMake(L2_X - OSC_TRIGGER_W / 2, L2_Y - OSC_TRIGGER_H / 2, OSC_TRIGGER_W, OSC_TRIGGER_H);
    [self styleButton:_l2Button label:@"LT" accent:[OnScreenControls accentNeutral] cornerR:OSC_TRIGGER_H / 2 fontSize:fs];
    [_view.layer addSublayer:_l2Button];

    _r2Button.frame = CGRectMake(R2_X - OSC_TRIGGER_W / 2, R2_Y - OSC_TRIGGER_H / 2, OSC_TRIGGER_W, OSC_TRIGGER_H);
    [self styleButton:_r2Button label:@"RT" accent:[OnScreenControls accentNeutral] cornerR:OSC_TRIGGER_H / 2 fontSize:fs];
    [_view.layer addSublayer:_r2Button];
}

- (void) drawSticks {
    // Left stick
    _leftStickBackground.frame = [self roundFrameAt:CGPointMake(LS_CENTER_X, LS_CENTER_Y) size:STICK_OUTER_SIZE];
    [self styleStickBackground:_leftStickBackground];
    [_view.layer addSublayer:_leftStickBackground];

    _leftStick.frame = [self roundFrameAt:CGPointMake(LS_CENTER_X, LS_CENTER_Y) size:STICK_INNER_SIZE];
    [self styleStickThumb:_leftStick];
    [_view.layer addSublayer:_leftStick];

    // Right stick
    _rightStickBackground.frame = [self roundFrameAt:CGPointMake(RS_CENTER_X, RS_CENTER_Y) size:STICK_OUTER_SIZE];
    [self styleStickBackground:_rightStickBackground];
    [_view.layer addSublayer:_rightStickBackground];

    _rightStick.frame = [self roundFrameAt:CGPointMake(RS_CENTER_X, RS_CENTER_Y) size:STICK_INNER_SIZE];
    [self styleStickThumb:_rightStick];
    [_view.layer addSublayer:_rightStick];
}

- (void) styleStickBackground:(CALayer*)layer {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.contents = nil;
    layer.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08].CGColor;
    layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.40].CGColor;
    layer.borderWidth = OSC_BORDER_WIDTH;
    layer.cornerRadius = layer.bounds.size.width / 2.0f;
    layer.opacity = OSC_BASE_OPACITY;
    [CATransaction commit];
}

- (void) styleStickThumb:(CALayer*)layer {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    layer.contents = nil;
    layer.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.30].CGColor;
    layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.65].CGColor;
    layer.borderWidth = OSC_BORDER_WIDTH;
    layer.cornerRadius = layer.bounds.size.width / 2.0f;
    layer.shadowColor = [UIColor blackColor].CGColor;
    layer.shadowOffset = CGSizeMake(0, 2);
    layer.shadowRadius = 5.0f;
    layer.shadowOpacity = 0.45f;
    layer.opacity = OSC_BASE_OPACITY + 0.15f;
    [CATransaction commit];
}

- (void) drawL3R3 {
    CGFloat fs = OSC_L3R3_SIZE * 0.34f;

    _l3Button.frame = [self roundFrameAt:CGPointMake(L3_X, L3_Y) size:OSC_L3R3_SIZE];
    [self styleButton:_l3Button label:@"L3" accent:[OnScreenControls accentGreen] cornerR:OSC_L3R3_SIZE / 2 fontSize:fs];
    [_view.layer addSublayer:_l3Button];

    _r3Button.frame = [self roundFrameAt:CGPointMake(R3_X, R3_Y) size:OSC_L3R3_SIZE];
    [self styleButton:_r3Button label:@"R3" accent:[OnScreenControls accentGreen] cornerR:OSC_L3R3_SIZE / 2 fontSize:fs];
    [_view.layer addSublayer:_r3Button];
}

- (void) hideButtons {
    [_aButton removeFromSuperlayer];
    [_bButton removeFromSuperlayer];
    [_xButton removeFromSuperlayer];
    [_yButton removeFromSuperlayer];
    [_upButton removeFromSuperlayer];
    [_downButton removeFromSuperlayer];
    [_leftButton removeFromSuperlayer];
    [_rightButton removeFromSuperlayer];
}

- (void) hideStartSelect {
    [_startButton removeFromSuperlayer];
    [_selectButton removeFromSuperlayer];
}

- (void) hideBumpers {
    [_l1Button removeFromSuperlayer];
    [_r1Button removeFromSuperlayer];
}

- (void) hideTriggers {
    [_l2Button removeFromSuperlayer];
    [_r2Button removeFromSuperlayer];
}

- (void) hideSticks {
    [_leftStickBackground removeFromSuperlayer];
    [_rightStickBackground removeFromSuperlayer];
    [_leftStick removeFromSuperlayer];
    [_rightStick removeFromSuperlayer];
    [self detachGlassFromLayer:_leftStickBackground];
    [self detachGlassFromLayer:_rightStickBackground];
}

- (void) hideL3R3 {
    [_l3Button removeFromSuperlayer];
    [_r3Button removeFromSuperlayer];
}

#pragma mark - Touch handling

- (BOOL) handleTouchMovedEvent:touches {
    BOOL updated = false;
    BOOL buttonTouch = false;
    float rsMaxX = RS_CENTER_X + STICK_OUTER_SIZE / 2;
    float rsMaxY = RS_CENTER_Y + STICK_OUTER_SIZE / 2;
    float rsMinX = RS_CENTER_X - STICK_OUTER_SIZE / 2;
    float rsMinY = RS_CENTER_Y - STICK_OUTER_SIZE / 2;
    float lsMaxX = LS_CENTER_X + STICK_OUTER_SIZE / 2;
    float lsMaxY = LS_CENTER_Y + STICK_OUTER_SIZE / 2;
    float lsMinX = LS_CENTER_X - STICK_OUTER_SIZE / 2;
    float lsMinY = LS_CENTER_Y - STICK_OUTER_SIZE / 2;
    
    for (UITouch* touch in touches) {
        CGPoint touchLocation = [touch locationInView:_view];
        float xLoc = touchLocation.x;
        float yLoc = touchLocation.y;
        if (touch == _lsTouch) {
            if (xLoc > lsMaxX) xLoc = lsMaxX;
            if (xLoc < lsMinX) xLoc = lsMinX;
            if (yLoc > lsMaxY) yLoc = lsMaxY;
            if (yLoc < lsMinY) yLoc = lsMinY;
            
            [self moveStickThumb:_leftStick toX:xLoc y:yLoc];
            
            float xStickVal = (xLoc - LS_CENTER_X) / (lsMaxX - LS_CENTER_X);
            float yStickVal = (yLoc - LS_CENTER_Y) / (lsMaxY - LS_CENTER_Y);
            
            if (fabsf(xStickVal) < STICK_DEAD_ZONE) xStickVal = 0;
            if (fabsf(yStickVal) < STICK_DEAD_ZONE) yStickVal = 0;
            
            if (_level == OnScreenControlsLevelKeyboard) {
                // Map the stick to arrow keys (8-way: diagonals hold two keys).
                CGFloat thr = 0.35f;
                int mask = 0;
                if (yStickVal < -thr) mask |= SK_UP;
                if (yStickVal >  thr) mask |= SK_DOWN;
                if (xStickVal < -thr) mask |= SK_LEFT;
                if (xStickVal >  thr) mask |= SK_RIGHT;
                [self updateStickDirectionKeys:mask];
                buttonTouch = true; // claim the touch without sending a gamepad event
            } else {
                [_controllerSupport updateLeftStick:_controller x:0x7FFE * xStickVal y:0x7FFE * -yStickVal];
                updated = true;
            }
        } else if (touch == _rsTouch) {
            if (xLoc > rsMaxX) xLoc = rsMaxX;
            if (xLoc < rsMinX) xLoc = rsMinX;
            if (yLoc > rsMaxY) yLoc = rsMaxY;
            if (yLoc < rsMinY) yLoc = rsMinY;
            
            [self moveStickThumb:_rightStick toX:xLoc y:yLoc];
            
            float xStickVal = (xLoc - RS_CENTER_X) / (rsMaxX - RS_CENTER_X);
            float yStickVal = (yLoc - RS_CENTER_Y) / (rsMaxY - RS_CENTER_Y);
            
            if (fabsf(xStickVal) < STICK_DEAD_ZONE) xStickVal = 0;
            if (fabsf(yStickVal) < STICK_DEAD_ZONE) yStickVal = 0;
            
            [_controllerSupport updateRightStick:_controller x:0x7FFE * xStickVal y:0x7FFE * -yStickVal];
            
            updated = true;
        } else if (touch == _dpadTouch) {
            [_controllerSupport clearButtonFlag:_controller
                                          flags:UP_FLAG | DOWN_FLAG | LEFT_FLAG | RIGHT_FLAG];
            [self setButton:_upButton pressed:NO];
            [self setButton:_downButton pressed:NO];
            [self setButton:_leftButton pressed:NO];
            [self setButton:_rightButton pressed:NO];
            
            // Allow the user to slide their finger to another d-pad button
            if ([_upButton.presentationLayer hitTest:touchLocation]) {
                [_controllerSupport setButtonFlag:_controller flags:UP_FLAG];
                [self setButton:_upButton pressed:YES];
                updated = true;
            } else if ([_downButton.presentationLayer hitTest:touchLocation]) {
                [_controllerSupport setButtonFlag:_controller flags:DOWN_FLAG];
                [self setButton:_downButton pressed:YES];
                updated = true;
            } else if ([_leftButton.presentationLayer hitTest:touchLocation]) {
                [_controllerSupport setButtonFlag:_controller flags:LEFT_FLAG];
                [self setButton:_leftButton pressed:YES];
                updated = true;
            } else if ([_rightButton.presentationLayer hitTest:touchLocation]) {
                [_controllerSupport setButtonFlag:_controller flags:RIGHT_FLAG];
                [self setButton:_rightButton pressed:YES];
                updated = true;
            }
            
            buttonTouch = true;
        } else if (touch == _aTouch) {
            buttonTouch = true;
        } else if (touch == _bTouch) {
            buttonTouch = true;
        } else if (touch == _xTouch) {
            buttonTouch = true;
        } else if (touch == _yTouch) {
            buttonTouch = true;
        } else if (touch == _startTouch) {
            buttonTouch = true;
        } else if (touch == _selectTouch) {
            buttonTouch = true;
        } else if (touch == _l1Touch) {
            buttonTouch = true;
        } else if (touch == _r1Touch) {
            buttonTouch = true;
        } else if (touch == _l2Touch) {
            buttonTouch = true;
        } else if (touch == _r2Touch) {
            buttonTouch = true;
        } else if (touch == _l3Touch) {
            buttonTouch = true;
        } else if (touch == _r3Touch) {
            buttonTouch = true;
        } else if ([_keyTouches containsObject:touch]) {
            // Keyboard-mapped button held; keep ownership of this touch.
            buttonTouch = true;
        }
        if ([_deadTouches containsObject:touch]) {
            updated = true;
        }
    }
    if (updated) {
        [_controllerSupport updateFinished:_controller];
    }
    return updated || buttonTouch;
}

// Maps a direction bit to its Win32 arrow-key VK code.
- (short) vkForStickBit:(int)bit {
    switch (bit) {
        case SK_UP:    return 0x26; // VK_UP
        case SK_DOWN:  return 0x28; // VK_DOWN
        case SK_LEFT:  return 0x25; // VK_LEFT
        case SK_RIGHT: return 0x27; // VK_RIGHT
    }
    return 0;
}

// Diffs the desired arrow-key set against what's currently held and sends the
// corresponding key down/up events (keyboard mode left stick).
//
// When the stick leaves the center (previous mask was 0) and engages a new
// direction, that direction is first "double-tapped" (a quick tap, then the
// sustained hold) so games that map double-tap to dash/run trigger correctly,
// e.g. pushing right fires "-> ->".
- (void) updateStickDirectionKeys:(int)newMask {
    int changed = _stickKeyMask ^ newMask;
    if (changed == 0) {
        return;
    }

    BOOL fromCenter = (_stickKeyMask == 0) && (newMask != 0);
    const int bits[4] = { SK_UP, SK_DOWN, SK_LEFT, SK_RIGHT };
    for (int i = 0; i < 4; i++) {
        int b = bits[i];
        if (changed & b) {
            BOOL down = ((newMask & b) != 0);
            if (down && fromCenter) {
                // Newly engaged from center: emit the first tap of a double-tap.
                [self sendStickDoubleTapForBit:b];
            } else {
                [_controllerSupport sendKeyboardEvent:[self vkForStickBit:b]
                                                 down:down];
            }
        }
    }
    _stickKeyMask = newMask;
}

// Emits a quick first tap (down + up) then holds the key down again, producing
// a double-tap. The held key is released later by the normal direction diffing
// when the stick changes direction or recenters.
- (void) sendStickDoubleTapForBit:(int)bit {
    short vk = [self vkForStickBit:bit];
    if (vk == 0) {
        return;
    }
    // First tap.
    [_controllerSupport sendKeyboardEvent:vk down:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.035 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self->_controllerSupport sendKeyboardEvent:vk down:NO];
        // Second press (held) after a short gap, but only if this direction is
        // still engaged.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.035 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            if (self->_stickKeyMask & bit) {
                [self->_controllerSupport sendKeyboardEvent:vk down:YES];
            }
        });
    });
}

// Move a stick thumb, keeping animations off so it tracks the finger 1:1.
- (void) moveStickThumb:(CALayer*)thumb toX:(float)xLoc y:(float)yLoc {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    thumb.frame = CGRectMake(xLoc - STICK_INNER_SIZE / 2, yLoc - STICK_INNER_SIZE / 2, STICK_INNER_SIZE, STICK_INNER_SIZE);
    [CATransaction commit];
}

// Spring the stick thumb back to center when released.
- (void) recenterStickThumb:(CALayer*)thumb centerX:(float)cx centerY:(float)cy {
    CGRect target = CGRectMake(cx - STICK_INNER_SIZE / 2, cy - STICK_INNER_SIZE / 2, STICK_INNER_SIZE, STICK_INNER_SIZE);
    [CATransaction begin];
    [CATransaction setAnimationDuration:0.12];
    [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    thumb.frame = target;
    [CATransaction commit];
}

- (BOOL)handleTouchDownEvent:touches {
    BOOL updated = false;
    BOOL stickTouch = false;
    BOOL keyTouch = false;
    for (UITouch* touch in touches) {
        CGPoint touchLocation = [touch locationInView:_view];
        
        if (_aButton.superlayer != nil && [_aButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:A_FLAG];
            [self setButton:_aButton pressed:YES];
            [self playHaptic:_hapticLight];
            _aTouch = touch;
            updated = true;
        } else if (_bButton.superlayer != nil && [_bButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:B_FLAG];
            [self setButton:_bButton pressed:YES];
            [self playHaptic:_hapticLight];
            _bTouch = touch;
            updated = true;
        } else if (_xButton.superlayer != nil && [_xButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:X_FLAG];
            [self setButton:_xButton pressed:YES];
            [self playHaptic:_hapticLight];
            _xTouch = touch;
            updated = true;
        } else if (_yButton.superlayer != nil && [_yButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:Y_FLAG];
            [self setButton:_yButton pressed:YES];
            [self playHaptic:_hapticLight];
            _yTouch = touch;
            updated = true;
        } else if (_upButton.superlayer != nil && [_upButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:UP_FLAG];
            [self setButton:_upButton pressed:YES];
            [self playHaptic:_hapticLight];
            _dpadTouch = touch;
            updated = true;
        } else if (_downButton.superlayer != nil && [_downButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:DOWN_FLAG];
            [self setButton:_downButton pressed:YES];
            [self playHaptic:_hapticLight];
            _dpadTouch = touch;
            updated = true;
        } else if (_leftButton.superlayer != nil && [_leftButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:LEFT_FLAG];
            [self setButton:_leftButton pressed:YES];
            [self playHaptic:_hapticLight];
            _dpadTouch = touch;
            updated = true;
        } else if (_rightButton.superlayer != nil && [_rightButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:RIGHT_FLAG];
            [self setButton:_rightButton pressed:YES];
            [self playHaptic:_hapticLight];
            _dpadTouch = touch;
            updated = true;
        } else if (_startButton.superlayer != nil && [_startButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:PLAY_FLAG];
            [self setButton:_startButton pressed:YES];
            [self playHaptic:_hapticMedium];
            _startTouch = touch;
            updated = true;
        } else if (_selectButton.superlayer != nil && [_selectButton.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:BACK_FLAG];
            [self setButton:_selectButton pressed:YES];
            [self playHaptic:_hapticMedium];
            _selectTouch = touch;
            updated = true;
        } else if (_l1Button.superlayer != nil && [_l1Button.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:LB_FLAG];
            [self setButton:_l1Button pressed:YES];
            [self playHaptic:_hapticLight];
            _l1Touch = touch;
            updated = true;
        } else if (_r1Button.superlayer != nil && [_r1Button.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport setButtonFlag:_controller flags:RB_FLAG];
            [self setButton:_r1Button pressed:YES];
            [self playHaptic:_hapticLight];
            _r1Touch = touch;
            updated = true;
        } else if (_l2Button.superlayer != nil && [_l2Button.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport updateLeftTrigger:_controller left:0xFF];
            [self setButton:_l2Button pressed:YES];
            [self playHaptic:_hapticLight];
            _l2Touch = touch;
            updated = true;
        } else if (_r2Button.superlayer != nil && [_r2Button.presentationLayer hitTest:touchLocation]) {
            [_controllerSupport updateRightTrigger:_controller right:0xFF];
            [self setButton:_r2Button pressed:YES];
            [self playHaptic:_hapticLight];
            _r2Touch = touch;
            updated = true;
        } else if (_l3Button.superlayer != nil && [_l3Button.presentationLayer hitTest:touchLocation]) {
            if (l3Set) {
                [_controllerSupport clearButtonFlag:_controller flags:LS_CLK_FLAG];
                [self setButton:_l3Button pressed:NO];
            } else {
                [_controllerSupport setButtonFlag:_controller flags:LS_CLK_FLAG];
                [self setButton:_l3Button pressed:YES];
            }
            [self playHaptic:_hapticMedium];
            l3Set = !l3Set;
            _l3Touch = touch;
            updated = true;
        } else if (_r3Button.superlayer != nil && [_r3Button.presentationLayer hitTest:touchLocation]) {
            if (r3Set) {
                [_controllerSupport clearButtonFlag:_controller flags:RS_CLK_FLAG];
                [self setButton:_r3Button pressed:NO];
            } else {
                [_controllerSupport setButtonFlag:_controller flags:RS_CLK_FLAG];
                [self setButton:_r3Button pressed:YES];
            }
            [self playHaptic:_hapticMedium];
            r3Set = !r3Set;
            _r3Touch = touch;
            updated = true;
        } else if (_leftStick.superlayer != nil && [_leftStickBackground.presentationLayer hitTest:touchLocation]) {
            if (l3TouchStart != nil) {
                // Find elapsed time and convert to milliseconds
                // Use (-) modifier to conversion since receiver is earlier than now
                double l3TouchTime = [l3TouchStart timeIntervalSinceNow] * -1000.0;
                if (l3TouchTime < STICK_CLICK_RATE) {
                    [_controllerSupport setButtonFlag:_controller flags:LS_CLK_FLAG];
                    updated = true;
                }
            }
            [self playHaptic:_hapticLight];
            _lsTouch = touch;
            stickTouch = true;
        } else if (_rightStick.superlayer != nil && [_rightStickBackground.presentationLayer hitTest:touchLocation]) {
            if (r3TouchStart != nil) {
                // Find elapsed time and convert to milliseconds
                // Use (-) modifier to conversion since receiver is earlier than now
                double r3TouchTime = [r3TouchStart timeIntervalSinceNow] * -1000.0;
                if (r3TouchTime < STICK_CLICK_RATE) {
                    [_controllerSupport setButtonFlag:_controller flags:RS_CLK_FLAG];
                    updated = true;
                }
            }
            [self playHaptic:_hapticLight];
            _rsTouch = touch;
            stickTouch = true;
        } else if ([self handleKeyboardButtonDown:touch]) {
            keyTouch = true;
        }
        if (!updated && !stickTouch && !keyTouch && [self isInDeadZone:touch]) {
            [_deadTouches addObject:touch];
            updated = true;
        }
    }
    if (updated) {
        [_controllerSupport updateFinished:_controller];
    }
    return updated || stickTouch || keyTouch;
}

// Returns YES if the touch hit one of the keyboard-mapped buttons.
- (BOOL) handleKeyboardButtonDown:(UITouch*)touch {
    CGPoint touchLocation = [touch locationInView:_view];
    for (NSUInteger i = 0; i < _keyButtons.count; i++) {
        CALayer* btn = _keyButtons[i];
        if (btn.superlayer != nil && [btn.presentationLayer hitTest:touchLocation]) {
            short vk = [_keyCodes[i] shortValue];
            [_controllerSupport sendKeyboardEvent:vk down:YES];
            [self setButton:btn pressed:YES];
            [self playHaptic:_hapticLight];
            _keyTouches[i] = touch;
            return YES;
        }
    }
    return NO;
}

- (BOOL)handleTouchUpEvent:touches {
    BOOL updated = false;
    BOOL touched = false;
    for (UITouch* touch in touches) {
        if (touch == _aTouch) {
            [_controllerSupport clearButtonFlag:_controller flags:A_FLAG];
            [self setButton:_aButton pressed:NO];
            _aTouch = nil;
            updated = true;
        } else if (touch == _bTouch) {
            [_controllerSupport clearButtonFlag:_controller flags:B_FLAG];
            [self setButton:_bButton pressed:NO];
            _bTouch = nil;
            updated = true;
        } else if (touch == _xTouch) {
            [_controllerSupport clearButtonFlag:_controller flags:X_FLAG];
            [self setButton:_xButton pressed:NO];
            _xTouch = nil;
            updated = true;
        } else if (touch == _yTouch) {
            [_controllerSupport clearButtonFlag:_controller flags:Y_FLAG];
            [self setButton:_yButton pressed:NO];
            _yTouch = nil;
            updated = true;
        } else if (touch == _dpadTouch) {
            [_controllerSupport clearButtonFlag:_controller
                                          flags:UP_FLAG | DOWN_FLAG | LEFT_FLAG | RIGHT_FLAG];
            [self setButton:_upButton pressed:NO];
            [self setButton:_downButton pressed:NO];
            [self setButton:_leftButton pressed:NO];
            [self setButton:_rightButton pressed:NO];
            _dpadTouch = nil;
            updated = true;
        } else if (touch == _startTouch) {
            [_controllerSupport clearButtonFlag:_controller flags:PLAY_FLAG];
            [self setButton:_startButton pressed:NO];
            _startTouch = nil;
            updated = true;
        } else if (touch == _selectTouch) {
            [_controllerSupport clearButtonFlag:_controller flags:BACK_FLAG];
            [self setButton:_selectButton pressed:NO];
            _selectTouch = nil;
            updated = true;
        } else if (touch == _l1Touch) {
            [_controllerSupport clearButtonFlag:_controller flags:LB_FLAG];
            [self setButton:_l1Button pressed:NO];
            _l1Touch = nil;
            updated = true;
        } else if (touch == _r1Touch) {
            [_controllerSupport clearButtonFlag:_controller flags:RB_FLAG];
            [self setButton:_r1Button pressed:NO];
            _r1Touch = nil;
            updated = true;
        } else if (touch == _l2Touch) {
            [_controllerSupport updateLeftTrigger:_controller left:0];
            [self setButton:_l2Button pressed:NO];
            _l2Touch = nil;
            updated = true;
        } else if (touch == _r2Touch) {
            [_controllerSupport updateRightTrigger:_controller right:0];
            [self setButton:_r2Button pressed:NO];
            _r2Touch = nil;
            updated = true;
        } else if (touch == _lsTouch) {
            [self recenterStickThumb:_leftStick centerX:LS_CENTER_X centerY:LS_CENTER_Y];
            if (_level == OnScreenControlsLevelKeyboard) {
                [self updateStickDirectionKeys:0]; // release any held arrow keys
            } else {
                [_controllerSupport updateLeftStick:_controller x:0 y:0];
                [_controllerSupport clearButtonFlag:_controller flags:LS_CLK_FLAG];
            }
            l3TouchStart = [NSDate date];
            _lsTouch = nil;
            updated = true;
        } else if (touch == _rsTouch) {
            [self recenterStickThumb:_rightStick centerX:RS_CENTER_X centerY:RS_CENTER_Y];
            [_controllerSupport updateRightStick:_controller x:0 y:0];
            [_controllerSupport clearButtonFlag:_controller flags:RS_CLK_FLAG];
            r3TouchStart = [NSDate date];
            _rsTouch = nil;
            updated = true;
        }
        else if (touch == _l3Touch) {
            _l3Touch = nil;
            touched = true;
        }
        else if (touch == _r3Touch) {
            _r3Touch = nil;
            touched = true;
        }
        else if ([self handleKeyboardButtonUp:touch]) {
            touched = true;
        }
        if ([_deadTouches containsObject:touch]) {
            [_deadTouches removeObject:touch];
            updated = true;
        }
    }
    if (updated) {
        [_controllerSupport updateFinished:_controller];
    }
    
    return updated || touched;
}

// Releases a keyboard-mapped button if this touch was holding one.
- (BOOL) handleKeyboardButtonUp:(UITouch*)touch {
    for (NSUInteger i = 0; i < _keyTouches.count; i++) {
        if (_keyTouches[i] == touch) {
            short vk = [_keyCodes[i] shortValue];
            [_controllerSupport sendKeyboardEvent:vk down:NO];
            [self setButton:_keyButtons[i] pressed:NO];
            _keyTouches[i] = [NSNull null];
            return YES;
        }
    }
    return NO;
}

- (BOOL) isInDeadZone:(UITouch*) touch {
    // Dynamically evaluate deadzones based on the controls
    // on screen at the time
    if (_leftButton.superlayer != nil && [self isDpadDeadZone:touch]) {
        return true;
    }
    else if (_aButton.superlayer != nil && [self isAbxyDeadZone:touch]) {
        return true;
    }
    else if (_l2Button.superlayer != nil && [self isTriggerDeadZone:touch]) {
        return true;
    }
    else if (_l1Button.superlayer != nil && [self isBumperDeadZone:touch]) {
        return true;
    }
    else if (_startButton.superlayer != nil && [self isStartSelectDeadZone:touch]) {
        return true;
    }
    else if (_l3Button.superlayer != nil && [self isL3R3DeadZone:touch]) {
        return true;
    }
    else if (_leftStickBackground.superlayer != nil && [self isStickDeadZone:touch]) {
        return true;
    }
    
    return false;
}

- (BOOL) isDpadDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_view.frame.origin.x
                     startY:_upButton.frame.origin.y
                       endX:_rightButton.frame.origin.x + _rightButton.frame.size.width
                       endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isAbxyDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_xButton.frame.origin.x
                     startY:_yButton.frame.origin.y
                       endX:_view.frame.origin.x + _view.frame.size.width
                       endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isBumperDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_view.frame.origin.x
                     startY:_l2Button.frame.origin.y + _l2Button.frame.size.height
                       endX:_l1Button.frame.origin.x + _l1Button.frame.size.width
                       endY:_upButton.frame.origin.y]
    || [self isDeadZone:touch
                 startX:_r2Button.frame.origin.x
                 startY:_r2Button.frame.origin.y + _r2Button.frame.size.height
                   endX:_view.frame.origin.x + _view.frame.size.width
                   endY:_yButton.frame.origin.y];
}

- (BOOL) isTriggerDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_view.frame.origin.x
                     startY:_l2Button.frame.origin.y
                       endX:_l2Button.frame.origin.x + _l2Button.frame.size.width
                       endY:_view.frame.origin.y + _view.frame.size.height]
    || [self isDeadZone:touch
                 startX:_r2Button.frame.origin.x
                 startY:_r2Button.frame.origin.y
                   endX:_view.frame.origin.x + _view.frame.size.width
                   endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isL3R3DeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_view.frame.origin.x
                     startY:_l3Button.frame.origin.y
                       endX:_view.frame.origin.x
                       endY:_view.frame.origin.y + _view.frame.size.height]
    || [self isDeadZone:touch
                 startX:_r3Button.frame.origin.x
                 startY:_r3Button.frame.origin.y
                   endX:_view.frame.origin.x + _view.frame.size.width
                   endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isStartSelectDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_startButton.frame.origin.x
                     startY:_startButton.frame.origin.y
                       endX:_view.frame.origin.x + _view.frame.size.width
                       endY:_view.frame.origin.y + _view.frame.size.height]
    || [self isDeadZone:touch
                 startX:_view.frame.origin.x
                 startY:_selectButton.frame.origin.y
                   endX:_selectButton.frame.origin.x + _selectButton.frame.size.width
                   endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isStickDeadZone:(UITouch*) touch {
    return [self isDeadZone:touch
                     startX:_leftStickBackground.frame.origin.x - 15
                     startY:_leftStickBackground.frame.origin.y - 15
                       endX:_leftStickBackground.frame.origin.x + _leftStickBackground.frame.size.width + 15
                       endY:_view.frame.origin.y + _view.frame.size.height]
    || [self isDeadZone:touch
                 startX:_rightStickBackground.frame.origin.x - 15
                 startY:_rightStickBackground.frame.origin.y - 15
                   endX:_rightStickBackground.frame.origin.x + _rightStickBackground.frame.size.width + 15
                   endY:_view.frame.origin.y + _view.frame.size.height];
}

- (BOOL) isDeadZone:(UITouch*) touch startX:(float)deadZoneStartX startY:(float)deadZoneStartY endX:(float)deadZoneEndX endY:(float)deadZoneEndY {
    deadZoneStartX -= DEAD_ZONE_PADDING;
    deadZoneStartY -= DEAD_ZONE_PADDING;
    deadZoneEndX += DEAD_ZONE_PADDING;
    deadZoneEndY += DEAD_ZONE_PADDING;
    
    CGPoint touchLocation = [touch locationInView:_view];
    return (touchLocation.x > deadZoneStartX && touchLocation.x < deadZoneEndX
            && touchLocation.y > deadZoneStartY && touchLocation.y < deadZoneEndY);
    
}

@end
