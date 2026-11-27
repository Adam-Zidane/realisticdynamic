// Realistic Dynamic 1.1.0 — an original Dynamic Island-style activity surface.
// Author: Zidane Adam. Rootless iOS 15+ arm64. Runs in SpringBoard only.
//
// Activities: Now Playing, notifications, charging, low power, ringer, calls,
// screen capture and best-effort Clock timer events. Includes spring animations,
// artwork-aware UI, optional volume HUD, haptics and an emergency disable file.
// Safety: create /var/mobile/realisticdynamic_off to disable, then respring.

#import <UIKit/UIKit.h>
#import <CallKit/CallKit.h>
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#include <notify.h>
#include <unistd.h>
#include <math.h>

#pragma mark - Preferences

static NSString *const kDomain = @"com.zidaneadam.realisticdynamic";
static NSString *const kPrefsNote = @"com.zidaneadam.realisticdynamic/prefs";

static id PrefObj(NSString *key) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kDomain);
    return CFBridgingRelease(v);
}
static BOOL PrefBool(NSString *key, BOOL def) {
    id v = PrefObj(key);
    return [v respondsToSelector:@selector(boolValue)] ? [v boolValue] : def;
}
static CGFloat PrefFloat(NSString *key, CGFloat def) {
    id v = PrefObj(key);
    return [v respondsToSelector:@selector(doubleValue)] ? (CGFloat)[v doubleValue] : def;
}
static void SetPref(NSString *key, id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key, (__bridge CFPropertyListRef)value, (__bridge CFStringRef)kDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
}

#pragma mark - Geometry

static CGFloat Base(void) { return MIN(UIScreen.mainScreen.bounds.size.width, 430.0) / 393.0; }
static CGFloat K(void) {
    CGFloat s = PrefFloat(@"scale", 1.0);
    s = MAX(0.6, MIN(1.6, s));
    return Base() * s;
}
static CGFloat TopY(void) { return MAX(0.0, PrefFloat(@"topOffset", 11.0)) * Base(); }
static CGFloat Damping(void) { return MAX(0.5, MIN(0.95, PrefFloat(@"damping", 0.72))); }

static void Haptic(void) {
    if (!PrefBool(@"haptics", YES)) return;
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
}

#pragma mark - Helpers

static UIColor *DefaultAccent(void) { return [UIColor colorWithRed:1.0 green:0.27 blue:0.43 alpha:1]; }
static UIColor *GreenColor(void) { return [UIColor colorWithRed:0.19 green:0.82 blue:0.35 alpha:1]; }
static UIColor *YellowColor(void) { return [UIColor colorWithRed:1.0 green:0.80 blue:0.0 alpha:1]; }
static UIColor *OrangeColor(void) { return [UIColor colorWithRed:1.0 green:0.62 blue:0.04 alpha:1]; }

static UIImage *Glyph(NSString *name, CGFloat pt) {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightSemibold];
    UIImage *i = [UIImage systemImageNamed:name withConfiguration:cfg];
    return [i imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static NSString *FmtTime(double s) {
    if (!isfinite(s) || s < 0) s = 0;
    int t = (int)s;
    return [NSString stringWithFormat:@"%d:%02d", t / 60, t % 60];
}

static UIColor *AverageColor(UIImage *img) {
    if (!img.CGImage) return nil;
    uint8_t px[4] = {0, 0, 0, 0};
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(px, 1, 1, 8, 4, cs, kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs);
    if (!ctx) return nil;
    CGContextSetInterpolationQuality(ctx, kCGInterpolationMedium);
    CGContextDrawImage(ctx, CGRectMake(0, 0, 1, 1), img.CGImage);
    CGContextRelease(ctx);
    UIColor *c = [UIColor colorWithRed:px[0] / 255.0 green:px[1] / 255.0 blue:px[2] / 255.0 alpha:1];
    CGFloat h, s, b, a;
    if ([c getHue:&h saturation:&s brightness:&b alpha:&a]) {
        s = MIN(1.0, s * 1.25);
        b = MAX(b, 0.8);
        c = [UIColor colorWithHue:h saturation:s brightness:b alpha:1];
    }
    return c;
}

#pragma mark - MediaRemote (private, loaded at runtime)

typedef void (*MRGetInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef void (*MRGetPlayingFn)(dispatch_queue_t, void (^)(Boolean));
typedef Boolean (*MRSendFn)(int, CFDictionaryRef);
typedef void (*MRRegisterFn)(dispatch_queue_t);
typedef void (*MRSetElapsedFn)(double);

static MRGetInfoFn MRGetInfo;
static MRGetPlayingFn MRGetPlaying;
static MRSendFn MRSend;
static MRRegisterFn MRRegister;
static MRSetElapsedFn MRSetElapsed;

enum { kCmdTogglePlayPause = 2, kCmdNext = 4, kCmdPrev = 5 };

#pragma mark - Config

typedef NS_ENUM(NSInteger, ISLLayout) { ISLLayoutIdle, ISLLayoutCompact, ISLLayoutMusic, ISLLayoutNote };

@interface ISLConfig : NSObject
@property (nonatomic) ISLLayout layout;
@property (nonatomic, strong) UIImage *leadingImage;
@property (nonatomic, strong) UIColor *leadingTint;
@property (nonatomic) BOOL leadingIsArt;
@property (nonatomic, copy) NSString *trailingText;
@property (nonatomic, strong) UIColor *trailingColor;
@property (nonatomic) BOOL showEQ;
@property (nonatomic) CGFloat compactWidth;
@property (nonatomic, strong) UIColor *accent;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy) NSString *subtitle;
@property (nonatomic) BOOL playing;
@property (nonatomic) double progress;
@property (nonatomic, copy) NSString *elapsedText;
@property (nonatomic, copy) NSString *remainingText;
@end
@implementation ISLConfig
@end

#pragma mark - Island view

@interface ISLView : UIView <UIGestureRecognizerDelegate>
@property (nonatomic, strong) ISLConfig *cfg;
@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic, copy) void (^onLongPress)(void);
@property (nonatomic, copy) void (^onSwipeUp)(void);
@property (nonatomic, copy) void (^onPrev)(void);
@property (nonatomic, copy) void (^onNext)(void);
@property (nonatomic, copy) void (^onPlay)(void);
@property (nonatomic, copy) void (^onSeek)(double fraction);
- (void)applyConfig:(ISLConfig *)c animated:(BOOL)animated;
- (void)setProgress:(double)p elapsed:(NSString *)e remaining:(NSString *)r;
@end

static UILabel *MakeLabel(void) {
    UILabel *l = [UILabel new];
    l.lineBreakMode = NSLineBreakByTruncatingTail;
    l.textColor = UIColor.whiteColor;
    return l;
}

@implementation ISLView {
    UIImageView *_leading;
    UILabel *_trailing, *_titleL, *_subL, *_elapsedL, *_remainL;
    NSArray<UIView *> *_bars;
    UIButton *_prev, *_play, *_next;
    UIView *_track, *_fill, *_trackHit;
    double _progress;
}

- (instancetype)init {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 126, 37)])) {
        self.backgroundColor = UIColor.blackColor;
        self.clipsToBounds = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;

        _leading = [UIImageView new];
        [self addSubview:_leading];

        _trailing = MakeLabel();
        _trailing.textAlignment = NSTextAlignmentRight;
        [self addSubview:_trailing];

        _titleL = MakeLabel();
        [self addSubview:_titleL];
        _subL = MakeLabel();
        _subL.textColor = [UIColor colorWithWhite:1 alpha:0.62];
        [self addSubview:_subL];

        NSMutableArray *bars = [NSMutableArray array];
        for (int i = 0; i < 3; i++) {
            UIView *b = [UIView new];
            b.layer.cornerRadius = 1.5;
            [self addSubview:b];
            [bars addObject:b];
        }
        _bars = bars;

        _track = [UIView new];
        _track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.22];
        _track.layer.cornerRadius = 2.5;
        [self addSubview:_track];
        _fill = [UIView new];
        _fill.backgroundColor = UIColor.whiteColor;
        _fill.layer.cornerRadius = 2.5;
        [self addSubview:_fill];
        _elapsedL = MakeLabel();
        _elapsedL.textColor = [UIColor colorWithWhite:1 alpha:0.55];
        [self addSubview:_elapsedL];
        _remainL = MakeLabel();
        _remainL.textColor = [UIColor colorWithWhite:1 alpha:0.55];
        _remainL.textAlignment = NSTextAlignmentRight;
        [self addSubview:_remainL];

        _trackHit = [UIView new];
        _trackHit.backgroundColor = UIColor.clearColor;
        [self addSubview:_trackHit];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(scrub:)];
        [_trackHit addGestureRecognizer:pan];
        UITapGestureRecognizer *seekTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(scrubTap:)];
        [_trackHit addGestureRecognizer:seekTap];

        _prev = [self controlWithAction:@selector(tapPrev)];
        _play = [self controlWithAction:@selector(tapPlay)];
        _next = [self controlWithAction:@selector(tapNext)];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap)];
        tap.delegate = self;
        [self addGestureRecognizer:tap];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        lp.minimumPressDuration = 0.35;
        lp.delegate = self;
        [self addGestureRecognizer:lp];
        UISwipeGestureRecognizer *sw = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeUp)];
        sw.direction = UISwipeGestureRecognizerDirectionUp;
        sw.delegate = self;
        [self addGestureRecognizer:sw];

        for (UIView *v in @[_leading, _trailing, _titleL, _subL, _elapsedL, _remainL, _track, _fill, _prev, _play, _next]) v.alpha = 0;
        for (UIView *b in _bars) b.alpha = 0;
    }
    return self;
}

- (UIButton *)controlWithAction:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.tintColor = UIColor.whiteColor;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:b];
    return b;
}

#pragma mark gestures

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t {
    UIView *v = t.view;
    if ([v isKindOfClass:[UIControl class]]) return NO;
    if (v == _trackHit) return NO;
    return YES;
}
- (void)handleTap { if (self.onTap) self.onTap(); }
- (void)handleLongPress:(UILongPressGestureRecognizer *)g { if (g.state == UIGestureRecognizerStateBegan && self.onLongPress) self.onLongPress(); }
- (void)handleSwipeUp { if (self.onSwipeUp) self.onSwipeUp(); }
- (void)tapPrev { if (self.onPrev) self.onPrev(); }
- (void)tapNext { if (self.onNext) self.onNext(); }
- (void)tapPlay { if (self.onPlay) self.onPlay(); }

- (double)fractionForGesture:(UIGestureRecognizer *)g {
    CGPoint p = [g locationInView:_track];
    CGFloat w = MAX(1, _track.bounds.size.width);
    return MAX(0, MIN(1, p.x / w));
}
- (void)scrub:(UIPanGestureRecognizer *)g {
    double f = [self fractionForGesture:g];
    _progress = f;
    [self updateFill];
    if (g.state == UIGestureRecognizerStateEnded && self.onSeek) self.onSeek(f);
}
- (void)scrubTap:(UITapGestureRecognizer *)g {
    double f = [self fractionForGesture:g];
    _progress = f;
    [self updateFill];
    if (self.onSeek) self.onSeek(f);
}

#pragma mark layout

- (CGRect)frameForConfig:(ISLConfig *)c {
    CGFloat k = K(), W = UIScreen.mainScreen.bounds.size.width;
    CGFloat w = 126 * k, h = 37 * k;
    switch (c.layout) {
        case ISLLayoutIdle: break;
        case ISLLayoutCompact: w = MAX(126, c.compactWidth) * k; break;
        case ISLLayoutMusic: w = MIN(371 * k, W - 24); h = 160 * k; break;
        case ISLLayoutNote: w = MIN(371 * k, W - 24); h = 84 * k; break;
    }
    w = MIN(w, W - 16);
    return CGRectMake((W - w) / 2.0, TopY(), w, h);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    ISLConfig *c = self.cfg;
    if (!c) return;
    CGFloat k = K(), w = self.bounds.size.width, h = self.bounds.size.height;
    self.layer.cornerRadius = MIN(h / 2.0, 46 * k);

    _trailing.font = [UIFont systemFontOfSize:14 * k weight:UIFontWeightSemibold];
    _titleL.font = [UIFont systemFontOfSize:(c.layout == ISLLayoutMusic ? 17 : 15) * k weight:UIFontWeightSemibold];
    _subL.font = [UIFont systemFontOfSize:(c.layout == ISLLayoutMusic ? 14 : 13) * k weight:UIFontWeightRegular];
    _elapsedL.font = [UIFont monospacedDigitSystemFontOfSize:11 * k weight:UIFontWeightMedium];
    _remainL.font = _elapsedL.font;

    CGFloat bw = 3 * k, gap = 2.5 * k, bh = 16 * k, barsW = bw * 3 + gap * 2;

    if (c.layout == ISLLayoutMusic) {
        _leading.frame = CGRectMake(16 * k, 16 * k, 60 * k, 60 * k);
        _leading.layer.cornerRadius = 12 * k;
        CGFloat bx = w - 16 * k - barsW;
        for (NSUInteger i = 0; i < 3; i++) _bars[i].frame = CGRectMake(bx + i * (bw + gap), 24 * k, bw, 18 * k);
        CGFloat tx = 88 * k, tw = MAX(0, bx - tx - 8 * k);
        _titleL.frame = CGRectMake(tx, 24 * k, tw, 22 * k);
        _subL.frame = CGRectMake(tx, 47 * k, tw, 18 * k);
        _track.frame = CGRectMake(16 * k, 90 * k, w - 32 * k, 5 * k);
        _trackHit.frame = CGRectMake(16 * k, 80 * k, w - 32 * k, 26 * k);
        _elapsedL.frame = CGRectMake(16 * k, 98 * k, 60 * k, 14 * k);
        _remainL.frame = CGRectMake(w - 16 * k - 60 * k, 98 * k, 60 * k, 14 * k);
        CGFloat cw = 56 * k, ch = 38 * k, cy = h - 12 * k - ch, cx = w / 2.0;
        _prev.frame = CGRectMake(cx - 72 * k - cw / 2.0, cy, cw, ch);
        _play.frame = CGRectMake(cx - cw / 2.0, cy, cw, ch);
        _next.frame = CGRectMake(cx + 72 * k - cw / 2.0, cy, cw, ch);
    } else if (c.layout == ISLLayoutNote) {
        _leading.frame = CGRectMake(16 * k, (h - 44 * k) / 2.0, 44 * k, 44 * k);
        _leading.layer.cornerRadius = 10 * k;
        CGFloat tx = 72 * k, tw = MAX(0, w - tx - 16 * k);
        _titleL.frame = CGRectMake(tx, 15 * k, tw, 20 * k);
        _subL.frame = CGRectMake(tx, 36 * k, tw, 34 * k);
    } else {
        _leading.frame = CGRectMake(11 * k, (h - 22 * k) / 2.0, 22 * k, 22 * k);
        _leading.layer.cornerRadius = c.leadingIsArt ? 6 * k : 0;
        _trailing.frame = CGRectMake(w - 12 * k - 100 * k, 0, 100 * k, h);
        CGFloat bx = w - 14 * k - barsW;
        for (NSUInteger i = 0; i < 3; i++) _bars[i].frame = CGRectMake(bx + i * (bw + gap), (h - bh) / 2.0, bw, bh);
    }
    [self updateFill];
}

- (void)updateFill {
    CGRect t = _track.frame;
    _fill.frame = CGRectMake(t.origin.x, t.origin.y, t.size.width * MAX(0, MIN(1, _progress)), t.size.height);
}

- (void)setProgress:(double)p elapsed:(NSString *)e remaining:(NSString *)r {
    _progress = p;
    _elapsedL.text = e;
    _remainL.text = r;
    [self updateFill];
}

- (void)applyAlphasForConfig:(ISLConfig *)c {
    BOOL idle = c.layout == ISLLayoutIdle;
    BOOL compact = c.layout == ISLLayoutCompact;
    BOOL music = c.layout == ISLLayoutMusic;
    BOOL note = c.layout == ISLLayoutNote;
    BOOL hasProg = music && c.progress >= 0;

    _leading.alpha = idle ? 0 : 1;
    _trailing.alpha = (compact && !c.showEQ && c.trailingText.length) ? 1 : 0;
    _titleL.alpha = (music || note) ? 1 : 0;
    _subL.alpha = (music || note) ? 1 : 0;
    CGFloat barsAlpha = ((compact && c.showEQ) || music) ? 1 : 0;
    for (UIView *b in _bars) b.alpha = barsAlpha;
    _track.alpha = hasProg ? 1 : 0;
    _fill.alpha = hasProg ? 1 : 0;
    _elapsedL.alpha = hasProg ? 1 : 0;
    _remainL.alpha = hasProg ? 1 : 0;
    _prev.alpha = music ? 1 : 0;
    _play.alpha = music ? 1 : 0;
    _next.alpha = music ? 1 : 0;
    _trackHit.userInteractionEnabled = hasProg;
}

- (void)setAllContentAlpha:(CGFloat)a {
    for (UIView *v in @[_leading, _trailing, _titleL, _subL, _elapsedL, _remainL, _track, _fill, _prev, _play, _next]) v.alpha = a;
    for (UIView *b in _bars) b.alpha = a;
}

#pragma mark content

- (void)updateContentForConfig:(ISLConfig *)c {
    CGFloat k = K();
    _leading.image = c.leadingImage;
    _leading.tintColor = c.leadingTint ?: UIColor.whiteColor;
    _leading.contentMode = c.leadingIsArt ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
    _leading.clipsToBounds = c.leadingIsArt;
    _leading.backgroundColor = c.leadingIsArt ? [UIColor colorWithWhite:0.16 alpha:1] : UIColor.clearColor;

    _trailing.text = c.trailingText;
    _trailing.textColor = c.trailingColor ?: UIColor.whiteColor;
    _titleL.text = c.title;
    _subL.text = c.subtitle;
    _subL.numberOfLines = (c.layout == ISLLayoutNote) ? 2 : 1;
    _subL.lineBreakMode = NSLineBreakByTruncatingTail;

    UIColor *accent = c.accent ?: DefaultAccent();
    for (UIView *b in _bars) b.backgroundColor = accent;
    _fill.backgroundColor = UIColor.whiteColor;

    UIImageSymbolConfiguration *big = [UIImageSymbolConfiguration configurationWithPointSize:26 * k weight:UIImageSymbolWeightBold];
    UIImageSymbolConfiguration *mid = [UIImageSymbolConfiguration configurationWithPointSize:22 * k weight:UIImageSymbolWeightBold];
    [_prev setImage:[UIImage systemImageNamed:@"backward.fill" withConfiguration:mid] forState:UIControlStateNormal];
    [_next setImage:[UIImage systemImageNamed:@"forward.fill" withConfiguration:mid] forState:UIControlStateNormal];
    [_play setImage:[UIImage systemImageNamed:(c.playing ? @"pause.fill" : @"play.fill") withConfiguration:big] forState:UIControlStateNormal];

    _progress = c.progress >= 0 ? c.progress : 0;
    _elapsedL.text = c.elapsedText;
    _remainL.text = c.remainingText;

    [self updateEqualizerForConfig:c];
}

- (void)updateEqualizerForConfig:(ISLConfig *)c {
    BOOL visible = (c.layout == ISLLayoutCompact && c.showEQ) || c.layout == ISLLayoutMusic;
    BOOL animate = visible && c.playing;
    for (NSUInteger i = 0; i < _bars.count; i++) {
        UIView *b = _bars[i];
        if (animate) {
            b.transform = CGAffineTransformIdentity;
            if (![b.layer animationForKey:@"eq"]) {
                CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"transform.scale.y"];
                a.fromValue = @0.25;
                a.toValue = @1.0;
                a.duration = 0.42 + 0.13 * i;
                a.autoreverses = YES;
                a.repeatCount = HUGE_VALF;
                a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
                [b.layer addAnimation:a forKey:@"eq"];
            }
        } else {
            [b.layer removeAnimationForKey:@"eq"];
            b.transform = CGAffineTransformMakeScale(1, 0.3);
        }
    }
}

#pragma mark apply

- (void)applyConfig:(ISLConfig *)c animated:(BOOL)animated {
    BOOL layoutChanged = (!self.cfg || self.cfg.layout != c.layout);
    self.cfg = c;
    self.layer.borderWidth = PrefBool(@"outline", NO) ? 0.65 : 0.0;
    self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.18].CGColor;
    [self updateContentForConfig:c];

    CGRect target = [self frameForConfig:c];
    void (^frameBlock)(void) = ^{
        self.frame = target;
        [self layoutIfNeeded];
    };
    void (^alphaBlock)(void) = ^{ [self applyAlphasForConfig:c]; };

    if (!animated) {
        frameBlock();
        alphaBlock();
        return;
    }

    UIViewAnimationOptions opts = UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction;
    CGFloat d = Damping();
    if (layoutChanged) {
        // old content out fast, container springs to the new shape, new content fades in
        [UIView animateWithDuration:0.10 delay:0 options:opts animations:^{ [self setAllContentAlpha:0]; } completion:nil];
        [UIView animateWithDuration:0.66 delay:0 usingSpringWithDamping:d initialSpringVelocity:0.55 options:opts animations:frameBlock completion:nil];
        [UIView animateWithDuration:0.30 delay:0.15 options:(opts | UIViewAnimationOptionCurveEaseOut) animations:alphaBlock completion:nil];
    } else {
        [UIView animateWithDuration:0.40 delay:0 usingSpringWithDamping:d initialSpringVelocity:0.3 options:opts animations:^{
            frameBlock();
            alphaBlock();
        } completion:nil];
    }
}

@end

#pragma mark - Pass-through window

@interface ISLWindow : UIWindow
@property (nonatomic, weak) UIView *island;
@end

@implementation ISLWindow
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *v = [super hitTest:point withEvent:event];
    if (!v) return nil;
    UIView *isl = self.island;
    if (!isl || isl.alpha < 0.05) return nil;
    CGPoint p = [self convertPoint:point toView:isl];
    return [isl pointInside:p withEvent:event] ? v : nil;
}
@end

#pragma mark - Controller state

static ISLWindow *sWindow;
static ISLView *sView;

static NSString *sTitle, *sArtist;
static UIImage *sArt;
static UIColor *sAccent;
static NSUInteger sArtHash;
static BOOL sPlaying, sHasTrack, sMusicExpanded, sLandscape;
static double sElapsed, sDuration, sRate;
static NSDate *sStamp;

static ISLConfig *sTransient;
static NSTimer *sTransientTimer, *sProgressTimer, *sCollapseTimer;

static void Render(BOOL animated);

static double CurrentElapsed(void) {
    double e = sElapsed;
    if (sPlaying && sStamp && sRate > 0) e += [[NSDate date] timeIntervalSinceDate:sStamp] * sRate;
    if (sDuration > 0) e = MIN(e, sDuration);
    return MAX(0, e);
}

static ISLConfig *MusicConfig(BOOL expanded) {
    ISLConfig *c = [ISLConfig new];
    c.layout = expanded ? ISLLayoutMusic : ISLLayoutCompact;
    c.leadingImage = sArt ?: Glyph(@"music.note", 13 * K());
    c.leadingIsArt = (sArt != nil);
    c.leadingTint = UIColor.whiteColor;
    c.showEQ = YES;
    c.accent = sAccent ?: DefaultAccent();
    c.compactWidth = 176;
    c.title = sTitle;
    c.subtitle = sArtist;
    c.playing = sPlaying;
    double el = CurrentElapsed();
    c.progress = sDuration > 0 ? el / sDuration : -1;
    c.elapsedText = FmtTime(el);
    c.remainingText = sDuration > 0 ? [@"-" stringByAppendingString:FmtTime(sDuration - el)] : @"";
    return c;
}

static void UpdateProgress(void) {
    if (!sView) return;
    double el = CurrentElapsed();
    [sView setProgress:(sDuration > 0 ? el / sDuration : 0)
               elapsed:FmtTime(el)
             remaining:(sDuration > 0 ? [@"-" stringByAppendingString:FmtTime(sDuration - el)] : @"")];
}

static void ScheduleCollapse(void) {
    [sCollapseTimer invalidate];
    sCollapseTimer = nil;
    if (!sMusicExpanded) return;
    sCollapseTimer = [NSTimer scheduledTimerWithTimeInterval:7.0 repeats:NO block:^(NSTimer *t) {
        sMusicExpanded = NO;
        Render(YES);
    }];
}

static void Render(BOOL animated) {
    if (!sView) return;
    BOOL enabled = PrefBool(@"enabled", YES);
    sWindow.hidden = (!enabled || sLandscape);

    ISLConfig *c;
    BOOL idle = NO;
    if (sTransient) {
        c = sTransient;
    } else if (sMusicExpanded && sHasTrack && PrefBool(@"music", YES) && (sPlaying || PrefBool(@"showPaused", YES))) {
        c = MusicConfig(YES);
    } else if (sHasTrack && (sPlaying || PrefBool(@"showPaused", YES)) && PrefBool(@"music", YES)) {
        c = MusicConfig(NO);
    } else {
        c = [ISLConfig new];
        c.layout = ISLLayoutIdle;
        idle = YES;
    }
    [sView applyConfig:c animated:animated];

    CGFloat targetAlpha = (idle && !PrefBool(@"alwaysShow", NO)) ? 0 : 1;
    if (fabs(sView.alpha - targetAlpha) > 0.01) {
        [UIView animateWithDuration:0.25 animations:^{ sView.alpha = targetAlpha; }];
    }

    [sProgressTimer invalidate];
    sProgressTimer = nil;
    if (c.layout == ISLLayoutMusic && sPlaying) {
        sProgressTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { UpdateProgress(); }];
    }
    if (c.layout == ISLLayoutMusic) ScheduleCollapse();
}

static void ShowTransient(ISLConfig *c, NSTimeInterval duration) {
    sTransient = c;
    [sTransientTimer invalidate];
    sTransientTimer = [NSTimer scheduledTimerWithTimeInterval:duration repeats:NO block:^(NSTimer *t) {
        sTransient = nil;
        Render(YES);
    }];
    Haptic();
    Render(YES);
}

static void DismissTransient(void) {
    [sTransientTimer invalidate];
    sTransientTimer = nil;
    sTransient = nil;
    Render(YES);
}


#pragma mark - Call activity (public CallKit observer)

static CXCallObserver *sCallObserver;

@interface ISLView (RDCallObserver) <CXCallObserverDelegate>
@end

@implementation ISLView (RDCallObserver)
- (void)callObserver:(CXCallObserver *)observer callChanged:(CXCall *)call {
    if (!PrefBool(@"calls", YES) || !call) return;

    NSString *label = call.hasConnected ? @"Call in Progress" :
        (call.hasEnded ? @"Call Ended" :
         (call.isOutgoing ? @"Outgoing Call" : @"Incoming Call"));

    ISLConfig *c = [ISLConfig new];
    c.layout = ISLLayoutCompact;
    c.leadingImage = Glyph(@"phone.fill", 14 * K());
    c.leadingTint = GreenColor();
    c.trailingText = label;
    c.trailingColor = UIColor.whiteColor;
    c.compactWidth = 224;
    ShowTransient(c, call.hasEnded ? 2.5 : 5.0);
}
@end


#pragma mark - Optional volume HUD

static AVAudioSession *sAudioSession;

@interface ISLView (RDVolumeObserver)
@end

@implementation ISLView (RDVolumeObserver)
- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey, id> *)change
                       context:(void *)context {
    if ([keyPath isEqualToString:@"outputVolume"]) {
        if (PrefBool(@"volume", NO)) {
            float value = [change[NSKeyValueChangeNewKey] floatValue];
            ISLConfig *c = [ISLConfig new];
            c.layout = ISLLayoutCompact;
            c.leadingImage = Glyph(@"speaker.wave.2.fill", 14 * K());
            c.leadingTint = UIColor.whiteColor;
            c.trailingText = [NSString stringWithFormat:@"%.0f%%", value * 100.0];
            c.trailingColor = UIColor.whiteColor;
            c.compactWidth = 164;
            ShowTransient(c, 1.6);
        }
        return;
    }
    [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
}
@end

#pragma mark - Activities

static void ShowCharging(void) {
    if (!PrefBool(@"charging", YES)) return;
    ISLConfig *c = [ISLConfig new];
    c.layout = ISLLayoutCompact;
    c.leadingImage = Glyph(@"bolt.fill", 14 * K());
    c.leadingTint = GreenColor();
    float lvl = UIDevice.currentDevice.batteryLevel;
    c.trailingText = lvl >= 0 ? [NSString stringWithFormat:@"%d%%", (int)roundf(lvl * 100)] : @"";
    c.trailingColor = UIColor.whiteColor;
    c.compactWidth = 182;
    ShowTransient(c, 3.0);
}

static void ShowLowPower(BOOL on) {
    if (!PrefBool(@"lowPower", YES)) return;
    ISLConfig *c = [ISLConfig new];
    c.layout = ISLLayoutCompact;
    c.leadingImage = Glyph(on ? @"battery.25" : @"battery.100", 15 * K());
    c.leadingTint = on ? YellowColor() : GreenColor();
    c.trailingText = on ? @"Low Power" : @"Power Normal";
    c.trailingColor = on ? YellowColor() : UIColor.whiteColor;
    c.compactWidth = 196;
    ShowTransient(c, 2.6);
}

static void ShowRinger(BOOL silent) {
    if (!PrefBool(@"ringer", YES)) return;
    ISLConfig *c = [ISLConfig new];
    c.layout = ISLLayoutCompact;
    c.leadingImage = Glyph(silent ? @"bell.slash.fill" : @"bell.fill", 14 * K());
    c.leadingTint = silent ? OrangeColor() : UIColor.whiteColor;
    c.trailingText = silent ? @"Silent" : @"Ring";
    c.trailingColor = silent ? OrangeColor() : UIColor.whiteColor;
    c.compactWidth = 172;
    ShowTransient(c, 2.2);
}

static NSString *Str(id v) { return [v isKindOfClass:[NSString class]] ? v : nil; }

static id KV(id obj, NSString *key) {
    if (!obj) return nil;
    if (![obj respondsToSelector:NSSelectorFromString(key)]) return nil;
    @try { return [obj valueForKey:key]; } @catch (__unused NSException *e) { return nil; }
}

static UIImage *AppIcon(NSString *bundleID) {
    if (!bundleID.length) return nil;
    SEL s = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if (![UIImage respondsToSelector:s]) return nil;
    @try {
        return ((UIImage * (*)(id, SEL, id, int, CGFloat))objc_msgSend)((id)[UIImage class], s, bundleID, 2, UIScreen.mainScreen.scale);
    } @catch (__unused NSException *e) {
        return nil;
    }
}

static void HandleNotification(id request) {
    if (!PrefBool(@"notifications", YES) || !request) return;
    id content = KV(request, @"content");
    NSString *title = Str(KV(content, @"title"));
    NSString *body = Str(KV(content, @"message"));
    NSString *header = Str(KV(content, @"header"));
    NSString *bundle = Str(KV(request, @"sectionIdentifier"));
    if (!title.length && !body.length && !header.length) return;

    UIImage *icon = AppIcon(bundle);
    ISLConfig *c = [ISLConfig new];
    c.layout = ISLLayoutNote;
    c.leadingImage = icon ?: Glyph(@"bell.fill", 22 * K());
    c.leadingIsArt = (icon != nil);
    c.leadingTint = UIColor.whiteColor;
    c.title = title.length ? title : header;
    c.subtitle = body.length ? body : (title.length ? header : @"");
    ShowTransient(c, 4.5);
}

static void HookNotifications(void) {
    Class cls = objc_getClass("NCNotificationDispatcher");
    SEL sel = NSSelectorFromString(@"postNotificationWithRequest:");
    Method m = cls ? class_getInstanceMethod(cls, sel) : NULL;
    if (!m) { NSLog(@"[Island] notification hook not available on this iOS"); return; }
    IMP orig = method_getImplementation(m);
    method_setImplementation(m, imp_implementationWithBlock(^(id self_, id request) {
        ((void (*)(id, SEL, id))orig)(self_, sel, request);
        dispatch_async(dispatch_get_main_queue(), ^{ HandleNotification(request); });
    }));
}

#pragma mark - Now playing

static void RefreshNowPlaying(void) {
    if (!MRGetInfo || !sView) return;
    MRGetInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
        NSDictionary *d = (__bridge NSDictionary *)info;
        NSString *t = Str(d[@"kMRMediaRemoteNowPlayingInfoTitle"]);
        NSString *a = Str(d[@"kMRMediaRemoteNowPlayingInfoArtist"]);
        NSData *art = [d[@"kMRMediaRemoteNowPlayingInfoArtworkData"] isKindOfClass:[NSData class]] ? d[@"kMRMediaRemoteNowPlayingInfoArtworkData"] : nil;
        id el = d[@"kMRMediaRemoteNowPlayingInfoElapsedTime"];
        id du = d[@"kMRMediaRemoteNowPlayingInfoDuration"];
        id rt = d[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"];
        id ts = d[@"kMRMediaRemoteNowPlayingInfoTimestamp"];

        sTitle = t;
        sArtist = a;
        sHasTrack = t.length > 0;
        sElapsed = [el respondsToSelector:@selector(doubleValue)] ? [el doubleValue] : 0;
        sDuration = [du respondsToSelector:@selector(doubleValue)] ? [du doubleValue] : 0;
        sRate = [rt respondsToSelector:@selector(doubleValue)] ? [rt doubleValue] : 1;
        sStamp = [ts isKindOfClass:[NSDate class]] ? ts : [NSDate date];

        if (art.length) {
            NSUInteger h = art.hash;
            if (h != sArtHash || !sArt) {
                sArtHash = h;
                sArt = [UIImage imageWithData:art];
                sAccent = AverageColor(sArt);
            }
        } else {
            sArt = nil;
            sAccent = nil;
            sArtHash = 0;
        }
        if (!sHasTrack) sMusicExpanded = NO;

        if (MRGetPlaying) {
            MRGetPlaying(dispatch_get_main_queue(), ^(Boolean p) {
                sPlaying = p;
                Render(YES);
            });
        } else {
            Render(YES);
        }
    });
}

#pragma mark - Prefs notification

static void PrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    dispatch_async(dispatch_get_main_queue(), ^{ Render(YES); });
}

#pragma mark - Setup

static int sRingerToken;
static uint64_t sRingerLast = UINT64_MAX;
static BOOL sWasCharging;

static void SetupIsland(void) {
    if (sWindow) return;
    CGRect b = UIScreen.mainScreen.bounds;
    sWindow = [[ISLWindow alloc] initWithFrame:b];
    sWindow.windowLevel = UIWindowLevelStatusBar + 1.0;
    sWindow.backgroundColor = UIColor.clearColor;
    UIViewController *vc = [UIViewController new];
    vc.view.backgroundColor = UIColor.clearColor;
    sWindow.rootViewController = vc;
    sView = [ISLView new];
    [vc.view addSubview:sView];
    sWindow.island = sView;

    // gestures -> behaviour
    sView.onTap = ^{
        if (sTransient) { if (sTransient.layout == ISLLayoutNote) DismissTransient(); return; }
        if (!sHasTrack) return;
        sMusicExpanded = !sMusicExpanded;
        Haptic();
        Render(YES);
    };
    sView.onLongPress = ^{
        if (sTransient || !sHasTrack || sMusicExpanded) return;
        sMusicExpanded = YES;
        Haptic();
        Render(YES);
    };
    sView.onSwipeUp = ^{
        if (sTransient) { DismissTransient(); return; }
        if (sMusicExpanded) { sMusicExpanded = NO; Render(YES); }
    };
    sView.onPlay = ^{ if (MRSend) MRSend(kCmdTogglePlayPause, NULL); ScheduleCollapse(); };
    sView.onNext = ^{ if (MRSend) MRSend(kCmdNext, NULL); ScheduleCollapse(); };
    sView.onPrev = ^{ if (MRSend) MRSend(kCmdPrev, NULL); ScheduleCollapse(); };
    sView.onSeek = ^(double f) {
        if (MRSetElapsed && sDuration > 0) {
            MRSetElapsed(f * sDuration);
            sElapsed = f * sDuration;
            sStamp = [NSDate date];
        }
        ScheduleCollapse();
    };

    sWindow.hidden = NO;
    Render(NO);

    // MediaRemote
    void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    if (h) {
        MRGetInfo = (MRGetInfoFn)dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
        MRGetPlaying = (MRGetPlayingFn)dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
        MRSend = (MRSendFn)dlsym(h, "MRMediaRemoteSendCommand");
        MRRegister = (MRRegisterFn)dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications");
        MRSetElapsed = (MRSetElapsedFn)dlsym(h, "MRMediaRemoteSetElapsedTime");
    }
    NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
    void (^mediaChanged)(NSNotification *) = ^(NSNotification *n) { RefreshNowPlaying(); };
    [nc addObserverForName:@"kMRMediaRemoteNowPlayingInfoDidChangeNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:mediaChanged];
    [nc addObserverForName:@"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:mediaChanged];
    if (MRRegister) MRRegister(dispatch_get_main_queue());
    RefreshNowPlaying();

    // Battery
    UIDevice.currentDevice.batteryMonitoringEnabled = YES;
    UIDeviceBatteryState st = UIDevice.currentDevice.batteryState;
    sWasCharging = (st == UIDeviceBatteryStateCharging || st == UIDeviceBatteryStateFull);
    [nc addObserverForName:UIDeviceBatteryStateDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        UIDeviceBatteryState s = UIDevice.currentDevice.batteryState;
        BOOL c = (s == UIDeviceBatteryStateCharging || s == UIDeviceBatteryStateFull);
        if (c && !sWasCharging) ShowCharging();
        sWasCharging = c;
    }];

    // Low power mode
    __block BOOL lastLPM = NSProcessInfo.processInfo.lowPowerModeEnabled;
    [nc addObserverForName:NSProcessInfoPowerStateDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        BOOL now = NSProcessInfo.processInfo.lowPowerModeEnabled;
        if (now != lastLPM) ShowLowPower(now);
        lastLPM = now;
    }];

    // Ringer switch
    notify_register_dispatch("com.apple.springboard.ringerstate", &sRingerToken, dispatch_get_main_queue(), ^(int t) {
        uint64_t s = 0;
        notify_get_state(t, &s);
        if (sRingerLast != UINT64_MAX && s != sRingerLast) {
            BOOL silent = (s == 0);
            if (PrefBool(@"invertRinger", NO)) silent = !silent;
            ShowRinger(silent);
        }
        sRingerLast = s;
    });
    uint64_t s0 = 0;
    notify_get_state(sRingerToken, &s0);
    sRingerLast = s0;

    // Orientation: hide in landscape
    [UIDevice.currentDevice beginGeneratingDeviceOrientationNotifications];
    [nc addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        UIDeviceOrientation o = UIDevice.currentDevice.orientation;
        if (UIDeviceOrientationIsLandscape(o)) sLandscape = YES;
        else if (UIDeviceOrientationIsPortrait(o)) sLandscape = NO;
        Render(NO);
    }];

    // Optional volume HUD. Observes the public outputVolume property without changing audio.
    sAudioSession = [AVAudioSession sharedInstance];
    @try {
        [sAudioSession addObserver:sView forKeyPath:@"outputVolume"
                           options:NSKeyValueObservingOptionNew context:NULL];
    } @catch (NSException *exception) {
        NSLog(@"[RealisticDynamic] Volume observation unavailable: %@", exception);
    }

    // Call state through public CallKit APIs. The tweak never answers or ends calls.
    sCallObserver = [CXCallObserver new];
    [sCallObserver setDelegate:(id<CXCallObserverDelegate>)sView queue:dispatch_get_main_queue()];

    // Screen capture status (recording and mirroring are reported together by iOS).
    __block BOOL wasCaptured = UIScreen.mainScreen.isCaptured;
    [nc addObserverForName:UIScreenCapturedDidChangeNotification object:nil
                     queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
        BOOL captured = UIScreen.mainScreen.isCaptured;
        if (captured != wasCaptured && PrefBool(@"recording", YES)) {
            ISLConfig *c = [ISLConfig new];
            c.layout = ISLLayoutCompact;
            c.leadingImage = Glyph(captured ? @"record.circle.fill" : @"record.circle", 14 * K());
            c.leadingTint = captured ? OrangeColor() : UIColor.whiteColor;
            c.trailingText = captured ? @"Screen Capture" : @"Capture Ended";
            c.trailingColor = UIColor.whiteColor;
            c.compactWidth = 210;
            ShowTransient(c, 3.0);
        }
        wasCaptured = captured;
    }];

    // Clock timer notifications vary by iOS build; this bridge is best-effort.
    for (NSString *timerName in @[
        @"MTTimerManagerTimersChanged",
        @"com.apple.mobiletimer.timerfired",
        @"com.apple.mobiletimer.timerpaused"
    ]) {
        [nc addObserverForName:timerName object:nil queue:NSOperationQueue.mainQueue
                    usingBlock:^(NSNotification *n) {
            if (!PrefBool(@"timers", YES)) return;
            ISLConfig *c = [ISLConfig new];
            c.layout = ISLLayoutCompact;
            c.leadingImage = Glyph(@"timer", 14 * K());
            c.leadingTint = [UIColor colorWithRed:0.35 green:0.65 blue:1.0 alpha:1.0];
            c.trailingText = @"Timer Updated";
            c.trailingColor = UIColor.whiteColor;
            c.compactWidth = 190;
            ShowTransient(c, 3.0);
        }];
    }

    // Notifications + live settings
    HookNotifications();
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, PrefsChanged,
                                    (__bridge CFStringRef)kPrefsNote, NULL, CFNotificationSuspensionBehaviorCoalesce);
}

#pragma mark - Crash-loop guard + entry point

static BOOL GuardAllows(void) {
    if (access("/var/mobile/realisticdynamic_off", F_OK) == 0) return NO;
    BOOL started = PrefBool(@"_started", NO), stable = PrefBool(@"_stable", YES);
    int fails = (int)PrefFloat(@"_fails", 0);
    fails = (started && !stable) ? fails + 1 : 0;
    if (fails >= 3) {
        SetPref(@"_fails", @0);
        SetPref(@"_started", @NO);
        SetPref(@"_stable", @YES);
        [@"" writeToFile:@"/var/mobile/realisticdynamic_off" atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return NO;
    }
    SetPref(@"_fails", @(fails));
    SetPref(@"_started", @YES);
    SetPref(@"_stable", @NO);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 25 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        SetPref(@"_stable", @YES);
        SetPref(@"_fails", @0);
    });
    return YES;
}

__attribute__((constructor)) static void island_init(void) {
    if (!GuardAllows()) return;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 4 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        SetupIsland();
    });
}
