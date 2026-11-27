// Realistic Dynamic 1.0.0 — Zidane Adam
// Rootless iOS 15+ Dynamic Island-style activity surface for notch-less iPhones.
// Runtime integrations are capability-checked; no private framework is hard-linked.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <CallKit/CallKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <notify.h>
#include <unistd.h>
#import <math.h>

static NSString * const RD_DOMAIN = @"com.zidaneadam.realisticdynamic";
static NSString * const RD_PREFS_NOTE = @"com.zidaneadam.realisticdynamic/prefs";
static id RDGet(NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)RD_DOMAIN);
    return CFBridgingRelease(value);
}
static BOOL RDBool(NSString *key, BOOL fallback) {
    id value = RDGet(key); return [value respondsToSelector:@selector(boolValue)] ? [value boolValue] : fallback;
}
static CGFloat RDFloat(NSString *key, CGFloat fallback) {
    id value = RDGet(key); return [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
}
static UIColor *RDColor(NSString *hex, CGFloat alpha) {
    unsigned int rgb = 0; NSScanner *scanner = [NSScanner scannerWithString:[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]];
    [scanner scanHexInt:&rgb]; return [UIColor colorWithRed:((rgb>>16)&255)/255.0 green:((rgb>>8)&255)/255.0 blue:(rgb&255)/255.0 alpha:alpha];
}
static UIImage *RDSymbol(NSString *name, CGFloat size) {
    if (@available(iOS 13.0, *)) return [[UIImage systemImageNamed:name withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:size weight:UIImageSymbolWeightSemibold]] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    return nil;
}
static NSString *RDTime(double seconds) {
    if (!isfinite(seconds) || seconds < 0) seconds = 0;
    NSInteger t = (NSInteger)seconds; return [NSString stringWithFormat:@"%ld:%02ld", (long)(t/60), (long)(t%60)];
}
static UIColor *RDAverageColor(UIImage *image) {
    if (!image.CGImage) return RDColor(@"#A78BFA",1);
    uint8_t px[4]={0,0,0,0}; CGColorSpaceRef cs=CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx=CGBitmapContextCreate(px,1,1,8,4,cs,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(cs); if(!ctx)return RDColor(@"#A78BFA",1);
    CGContextSetInterpolationQuality(ctx,kCGInterpolationMedium); CGContextDrawImage(ctx,CGRectMake(0,0,1,1),image.CGImage); CGContextRelease(ctx);
    UIColor*c=[UIColor colorWithRed:px[0]/255.0 green:px[1]/255.0 blue:px[2]/255.0 alpha:1]; CGFloat h=0,s=0,b=0,a=1;
    if([c getHue:&h saturation:&s brightness:&b alpha:&a]) c=[UIColor colorWithHue:h saturation:MIN(1,s*1.3) brightness:MAX(.78,b) alpha:1];
    return c;
}
static void RDHaptic(void) {
    if (!RDBool(@"haptics", YES)) return;
    if (@available(iOS 10.0, *)) { UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight]; [g prepare]; [g impactOccurred]; }
}

typedef NS_ENUM(NSInteger, RDMode) { RDModeIdle, RDModeCompact, RDModeExpanded, RDModeNotice };
@interface RDModel : NSObject
@property(nonatomic) RDMode mode;
@property(nonatomic,copy) NSString *symbol, *title, *detail, *trailing;
@property(nonatomic,strong) UIImage *image;
@property(nonatomic,strong) UIColor *tint;
@property(nonatomic) BOOL playing;
@property(nonatomic) double progress;
@property(nonatomic) BOOL hasProgress;
@end
@implementation RDModel @end

@interface RDIslandView : UIView
@property(nonatomic,copy) void (^tap)(void);
@property(nonatomic,copy) void (^longPress)(void);
@property(nonatomic,copy) void (^swipe)(void);
@property(nonatomic,copy) void (^play)(void);
@property(nonatomic,copy) void (^next)(void);
@property(nonatomic,copy) void (^previous)(void);
@property(nonatomic,copy) void (^seek)(double);
@property(nonatomic,strong) RDModel *model;
- (void)render:(RDModel *)model animated:(BOOL)animated;
- (void)updateProgress:(double)value elapsed:(NSString *)elapsed remaining:(NSString *)remaining;
@end

@implementation RDIslandView {
    UIImageView *_icon; UILabel *_titleLabel, *_detailLabel, *_rightLabel, *_elapsedLabel, *_remainingLabel;
    UIView *_track, *_trackFill, *_trackTouch; UIButton *_playButton, *_nextButton, *_prevButton;
    NSArray<UIView *> *_eq; double _progress;
}
- (instancetype)init {
    if ((self=[super initWithFrame:CGRectMake(0,0,126,37)])) {
        self.backgroundColor=UIColor.blackColor; self.clipsToBounds=YES; self.layer.cornerCurve=kCACornerCurveContinuous;
        self.layer.borderWidth=RDBool(@"outline", NO)?0.7:0; self.layer.borderColor=[UIColor colorWithWhite:1 alpha:0.18].CGColor;
        self.layer.shadowColor=UIColor.blackColor.CGColor; self.layer.shadowOpacity=0.24; self.layer.shadowRadius=12; self.layer.shadowOffset=CGSizeMake(0,5);
        _icon=[UIImageView new]; _icon.contentMode=UIViewContentModeScaleAspectFill; [self addSubview:_icon];
        _titleLabel=[UILabel new]; _titleLabel.textColor=UIColor.whiteColor; _titleLabel.font=[UIFont systemFontOfSize:15 weight:UIFontWeightSemibold]; _titleLabel.lineBreakMode=NSLineBreakByTruncatingTail; [self addSubview:_titleLabel];
        _detailLabel=[UILabel new]; _detailLabel.textColor=[UIColor colorWithWhite:1 alpha:.62]; _detailLabel.font=[UIFont systemFontOfSize:12 weight:UIFontWeightRegular]; _detailLabel.lineBreakMode=NSLineBreakByTruncatingTail; [self addSubview:_detailLabel];
        _rightLabel=[UILabel new]; _rightLabel.textColor=UIColor.whiteColor; _rightLabel.textAlignment=NSTextAlignmentRight; _rightLabel.font=[UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold]; [self addSubview:_rightLabel];
        NSMutableArray *bars=[NSMutableArray array]; for (int i=0;i<4;i++){ UIView *b=[UIView new]; b.backgroundColor=RDColor(@"#6EE7B7",1); b.layer.cornerRadius=1.5; [self addSubview:b]; [bars addObject:b]; } _eq=bars;
        _track=[UIView new]; _track.backgroundColor=[UIColor colorWithWhite:1 alpha:.22]; _track.layer.cornerRadius=2; [self addSubview:_track];
        _trackFill=[UIView new]; _trackFill.backgroundColor=UIColor.whiteColor; _trackFill.layer.cornerRadius=2; [self addSubview:_trackFill];
        _elapsedLabel=[UILabel new]; _remainingLabel=[UILabel new]; for (UILabel *l in @[_elapsedLabel,_remainingLabel]) { l.textColor=[UIColor colorWithWhite:1 alpha:.55]; l.font=[UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightMedium]; [self addSubview:l]; }
        _remainingLabel.textAlignment=NSTextAlignmentRight;
        _trackTouch=[UIView new]; _trackTouch.backgroundColor=UIColor.clearColor; _trackTouch.userInteractionEnabled=YES; [self addSubview:_trackTouch];
        UIPanGestureRecognizer *pan=[[UIPanGestureRecognizer alloc]initWithTarget:self action:@selector(scrub:)]; [_trackTouch addGestureRecognizer:pan];
        UITapGestureRecognizer *seekTap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(scrubTap:)]; [_trackTouch addGestureRecognizer:seekTap];
        _prevButton=[self button:@selector(prevPressed)]; _playButton=[self button:@selector(playPressed)]; _nextButton=[self button:@selector(nextPressed)];
        UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(tapped)]; tap.delegate=(id<UIGestureRecognizerDelegate>)self; [self addGestureRecognizer:tap];
        UILongPressGestureRecognizer *hold=[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(held:)]; hold.minimumPressDuration=.38; hold.delegate=(id<UIGestureRecognizerDelegate>)self; [self addGestureRecognizer:hold];
        UISwipeGestureRecognizer *sw=[[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(swiped)]; sw.direction=UISwipeGestureRecognizerDirectionUp; sw.delegate=(id<UIGestureRecognizerDelegate>)self; [self addGestureRecognizer:sw];
    } return self;
}
- (UIButton *)button:(SEL)action { UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem]; b.tintColor=UIColor.whiteColor; [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside]; [self addSubview:b]; return b; }
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldReceiveTouch:(UITouch *)t { return ![t.view isKindOfClass:UIControl.class] && t.view!=_trackTouch; }
- (void)tapped { if(self.tap)self.tap(); }
- (void)held:(UILongPressGestureRecognizer *)g { if(g.state==UIGestureRecognizerStateBegan && self.longPress)self.longPress(); }
- (void)swiped { if(self.swipe)self.swipe(); }
- (void)playPressed { if(self.play)self.play(); }
- (void)nextPressed { if(self.next)self.next(); }
- (void)prevPressed { if(self.previous)self.previous(); }
- (double)fraction:(UIGestureRecognizer *)g { CGPoint p=[g locationInView:_track]; return MAX(0,MIN(1,p.x/MAX(1,_track.bounds.size.width))); }
- (void)scrub:(UIPanGestureRecognizer *)g { _progress=[self fraction:g]; [self layoutFill]; if(g.state==UIGestureRecognizerStateEnded && self.seek)self.seek(_progress); }
- (void)scrubTap:(UITapGestureRecognizer *)g { _progress=[self fraction:g]; [self layoutFill]; if(self.seek)self.seek(_progress); }
- (void)layoutSubviews {
    [super layoutSubviews]; CGFloat w=self.bounds.size.width,h=self.bounds.size.height,k=MIN(1.0,UIScreen.mainScreen.bounds.size.width/390.0);
    BOOL expanded=self.model.mode==RDModeExpanded, notice=self.model.mode==RDModeNotice;
    self.layer.cornerRadius=MIN(h/2,expanded?30:notice?24:22);
    if(expanded){
        _icon.frame=CGRectMake(14*k,14*k,58*k,58*k); _icon.layer.cornerRadius=11*k; _icon.clipsToBounds=YES;
        _titleLabel.frame=CGRectMake(82*k,20*k,w-120*k,22*k); _detailLabel.frame=CGRectMake(82*k,43*k,w-120*k,18*k);
        CGFloat tx=14*k,tw=w-28*k; _track.frame=CGRectMake(tx,83*k,tw,4*k); _trackTouch.frame=CGRectMake(tx,75*k,tw,22*k);
        _elapsedLabel.frame=CGRectMake(tx,90*k,65*k,14*k); _remainingLabel.frame=CGRectMake(w-79*k,90*k,65*k,14*k);
        CGFloat cy=h-13*k-38*k,cx=w/2; _prevButton.frame=CGRectMake(cx-84*k,cy,48*k,38*k); _playButton.frame=CGRectMake(cx-24*k,cy,48*k,38*k); _nextButton.frame=CGRectMake(cx+36*k,cy,48*k,38*k);
        for(int i=0;i<4;i++)_eq[i].frame=CGRectMake(w-25*k+i*4*k,25*k,2.5*k,15*k);
    } else if(notice){
        _icon.frame=CGRectMake(12*k,(h-38*k)/2,38*k,38*k); _icon.layer.cornerRadius=9*k; _icon.clipsToBounds=YES;
        _titleLabel.frame=CGRectMake(60*k,12*k,w-72*k,20*k); _detailLabel.frame=CGRectMake(60*k,33*k,w-72*k,MAX(18*k,h-39*k));
        _rightLabel.frame=CGRectZero; _track.frame=_trackFill.frame=_trackTouch.frame=CGRectZero;
    } else {
        _icon.frame=CGRectMake(11*k,(h-21*k)/2,21*k,21*k); _icon.layer.cornerRadius=6*k; _icon.clipsToBounds=YES;
        _titleLabel.frame=CGRectZero; _detailLabel.frame=CGRectZero; _rightLabel.frame=CGRectMake(w-75*k,0,62*k,h);
        for(int i=0;i<4;i++)_eq[i].frame=CGRectMake(w-23*k+i*4*k,(h-14*k)/2,2.5*k,14*k);
        _track.frame=_trackFill.frame=_trackTouch.frame=CGRectZero;
    }
    [self layoutFill];
}
- (void)layoutFill { CGRect r=_track.frame; _trackFill.frame=CGRectMake(r.origin.x,r.origin.y,r.size.width*MAX(0,MIN(1,_progress)),r.size.height); }
- (void)updateProgress:(double)v elapsed:(NSString *)e remaining:(NSString *)r { _progress=v; _elapsedLabel.text=e; _remainingLabel.text=r; [self layoutFill]; }
- (void)render:(RDModel *)m animated:(BOOL)animated {
    self.model=m; CGFloat sw=UIScreen.mainScreen.bounds.size.width,k=MIN(1.0,sw/390.0); CGFloat width=126*k,height=37*k;
    if(m.mode==RDModeCompact){ width=MAX(142, m.trailing.length?175:164)*k; }
    if(m.mode==RDModeNotice){ width=MIN(sw-30,340*k); height=64*k; }
    if(m.mode==RDModeExpanded){ width=MIN(sw-28,350*k); height=146*k; }
    _icon.image=m.image?:RDSymbol(m.symbol?:@"waveform",m.mode==RDModeExpanded?24:17); _icon.tintColor=m.tint?:UIColor.whiteColor;
    _icon.backgroundColor=m.image?[UIColor colorWithWhite:.12 alpha:1]:UIColor.clearColor;
    _titleLabel.text=m.title; _detailLabel.text=m.detail; _rightLabel.text=m.trailing;
    _rightLabel.textColor=m.tint?:UIColor.whiteColor;
    if(m.mode==RDModeExpanded){
        UIImageSymbolConfiguration *big=[UIImageSymbolConfiguration configurationWithPointSize:23 weight:UIImageSymbolWeightBold];
        UIImageSymbolConfiguration *small=[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold];
        [_playButton setImage:[UIImage systemImageNamed:(m.playing?@"pause.fill":@"play.fill") withConfiguration:big] forState:UIControlStateNormal];
        [_prevButton setImage:[UIImage systemImageNamed:@"backward.fill" withConfiguration:small] forState:UIControlStateNormal]; [_nextButton setImage:[UIImage systemImageNamed:@"forward.fill" withConfiguration:small] forState:UIControlStateNormal];
    }
    BOOL eq=(m.mode==RDModeCompact && m.playing); for(UIView *b in _eq){ b.backgroundColor=m.tint?:RDColor(@"#6EE7B7",1); b.hidden=!eq; if(eq && ![b.layer animationForKey:@"rd.eq"]){ CABasicAnimation *a=[CABasicAnimation animationWithKeyPath:@"transform.scale.y"]; a.fromValue=@.22; a.toValue=@1; a.duration=.38+arc4random_uniform(30)/100.0; a.autoreverses=YES; a.repeatCount=HUGE_VALF; [b.layer addAnimation:a forKey:@"rd.eq"]; } else if(!eq)[b.layer removeAnimationForKey:@"rd.eq"]; }
    _rightLabel.hidden=(m.mode==RDModeNotice); _titleLabel.hidden=(m.mode!=RDModeExpanded && m.mode!=RDModeNotice); _detailLabel.hidden=_titleLabel.hidden;
    BOOL prog=(m.mode==RDModeExpanded && m.hasProgress); _track.hidden=!prog; _trackFill.hidden=!prog; _trackTouch.hidden=!prog; _elapsedLabel.hidden=!prog; _remainingLabel.hidden=!prog;
    _prevButton.hidden=_playButton.hidden=_nextButton.hidden=(m.mode!=RDModeExpanded);
    CGRect target=CGRectMake((sw-width)/2,MAX(4,RDFloat(@"topOffset",11)),width,height);
    void(^changes)(void)=^{ self.layer.borderWidth=RDBool(@"outline",NO)?0.7:0; self.frame=target; [self setNeedsLayout]; [self layoutIfNeeded]; };
    if(animated) [UIView animateWithDuration:.48 delay:0 usingSpringWithDamping:.78 initialSpringVelocity:.55 options:UIViewAnimationOptionBeginFromCurrentState|UIViewAnimationOptionAllowUserInteraction animations:changes completion:nil]; else changes();
}
@end

@interface RDWindow : UIWindow
@property(nonatomic,weak) UIView *island;
@end
@implementation RDWindow
- (UIView *)hitTest:(CGPoint)p withEvent:(UIEvent *)e { UIView *v=[super hitTest:p withEvent:e]; if(!v||!self.island||self.island.alpha<.05)return nil; CGPoint q=[self convertPoint:p toView:self.island]; return [self.island pointInside:q withEvent:e]?v:nil; }
@end

static RDWindow *gWindow; static RDIslandView *gIsland; static RDModel *gTransient;
static NSTimer *gTransientTimer,*gProgressTimer,*gCollapseTimer;
static NSString *gTrackTitle,*gTrackArtist; static UIImage *gArtwork; static UIColor *gArtworkTint;
static BOOL gPlaying,gHasTrack,gExpanded,gLandscape,gWasCharging,gRecording; static int gRingerToken; static uint64_t gRingerState=UINT64_MAX; static double gElapsed,gDuration,gRate; static NSDate *gStamp;
static void (*MRInfo)(dispatch_queue_t,void(^)(CFDictionaryRef)); static void (*MRPlaying)(dispatch_queue_t,void(^)(Boolean)); static Boolean (*MRCommand)(int,CFDictionaryRef); static void (*MRSetElapsed)(double);
enum { RDPlayPause=2,RDNext=4,RDPrevious=5 };
static double RDCurrentElapsed(void){ double x=gElapsed; if(gPlaying&&gStamp&&gRate>0)x+=[[NSDate date] timeIntervalSinceDate:gStamp]*gRate; return gDuration>0?MIN(gDuration,MAX(0,x)):MAX(0,x); }
static RDModel *RDIdle(void){ RDModel*m=[RDModel new];m.mode=RDModeIdle;return m; }
static RDModel *RDMusic(BOOL expanded){ RDModel*m=[RDModel new];m.mode=expanded?RDModeExpanded:RDModeCompact;m.symbol=@"music.note";m.image=gArtwork;m.tint=gArtworkTint?:RDColor(@"#A78BFA",1);m.title=gTrackTitle?:@"Now Playing";m.detail=gTrackArtist?:@"";m.playing=gPlaying;m.trailing=expanded?nil:(gPlaying?@"♫":@"Ⅱ");m.progress=gDuration>0?RDCurrentElapsed()/gDuration:0;m.hasProgress=gDuration>0;return m; }
static void RDRender(BOOL animated);
static void RDShow(RDModel*m,NSTimeInterval duration){ if(!gIsland)return;gTransient=m;[gTransientTimer invalidate];gTransientTimer=[NSTimer scheduledTimerWithTimeInterval:duration repeats:NO block:^(NSTimer*t){gTransient=nil;RDRender(YES);}];RDHaptic();RDRender(YES); }
static void RDProgress(void){ if(!gIsland||!gExpanded||!gPlaying)return;[gIsland updateProgress:gDuration>0?RDCurrentElapsed()/gDuration:0 elapsed:RDTime(RDCurrentElapsed()) remaining:gDuration>0?[NSString stringWithFormat:@"−%@",RDTime(gDuration-RDCurrentElapsed())]:@""]; }
static void RDScheduleCollapse(void){[gCollapseTimer invalidate];gCollapseTimer=[NSTimer scheduledTimerWithTimeInterval:12 repeats:NO block:^(NSTimer*t){gExpanded=NO;RDRender(YES);}];}
static void RDRender(BOOL animated){ if(!gIsland)return;BOOL enabled=RDBool(@"enabled",YES);gWindow.hidden=!enabled||gLandscape;
    RDModel*m=gTransient?:((gHasTrack&&(gPlaying||RDBool(@"showPaused",YES))&&RDBool(@"music",YES))?RDMusic(gExpanded):RDIdle());
    if(m.mode==RDModeIdle && !RDBool(@"alwaysShow",NO)){gIsland.alpha=0;}else{gIsland.alpha=1;[gIsland render:m animated:animated];}
    [gProgressTimer invalidate];gProgressTimer=nil;if(m.mode==RDModeExpanded&&gPlaying)gProgressTimer=[NSTimer scheduledTimerWithTimeInterval:.5 repeats:YES block:^(NSTimer*t){RDProgress();}];
}
static NSString *RDString(id x){return [x isKindOfClass:NSString.class]?x:nil;}
static void RDRefreshMedia(void){if(!MRInfo||!gIsland)return;MRInfo(dispatch_get_main_queue(),^(CFDictionaryRef raw){NSDictionary*d=raw?(__bridge NSDictionary*)raw:@{};gTrackTitle=RDString(d[@"kMRMediaRemoteNowPlayingInfoTitle"]);gTrackArtist=RDString(d[@"kMRMediaRemoteNowPlayingInfoArtist"]);gHasTrack=gTrackTitle.length>0;id el=d[@"kMRMediaRemoteNowPlayingInfoElapsedTime"],du=d[@"kMRMediaRemoteNowPlayingInfoDuration"],ra=d[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"],ts=d[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
    gElapsed=[el respondsToSelector:@selector(doubleValue)]?[el doubleValue]:0;gDuration=[du respondsToSelector:@selector(doubleValue)]?[du doubleValue]:0;gRate=[ra respondsToSelector:@selector(doubleValue)]?[ra doubleValue]:1;gStamp=[ts isKindOfClass:NSDate.class]?ts:[NSDate date];NSData*art=[d[@"kMRMediaRemoteNowPlayingInfoArtworkData"] isKindOfClass:NSData.class]?d[@"kMRMediaRemoteNowPlayingInfoArtworkData"]:nil;if(art){gArtwork=[UIImage imageWithData:art];gArtworkTint=RDAverageColor(gArtwork);}else{gArtwork=nil;gArtworkTint=nil;}if(!gHasTrack)gExpanded=NO;
    if(MRPlaying)MRPlaying(dispatch_get_main_queue(),^(Boolean p){gPlaying=p;RDRender(YES);});else RDRender(YES);
 });}
static void RDActivity(NSString*symbol,NSString*title,NSString*detail,NSString*trailing,UIColor*tint,NSTimeInterval time){RDModel*m=[RDModel new];m.mode=RDModeCompact;m.symbol=symbol;m.title=title;m.detail=detail;m.trailing=trailing?:((detail.length)?detail:title);m.tint=tint;RDShow(m,time);}
static void RDSetupObservers(void){NSNotificationCenter*nc=NSNotificationCenter.defaultCenter;
    UIDevice.currentDevice.batteryMonitoringEnabled=YES;gWasCharging=(UIDevice.currentDevice.batteryState==UIDeviceBatteryStateCharging||UIDevice.currentDevice.batteryState==UIDeviceBatteryStateFull);
    [nc addObserverForName:UIDeviceBatteryStateDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){UIDeviceBatteryState s=UIDevice.currentDevice.batteryState;BOOL c=s==UIDeviceBatteryStateCharging||s==UIDeviceBatteryStateFull;if(c&&!gWasCharging&&RDBool(@"charging",YES)){float b=UIDevice.currentDevice.batteryLevel;RDActivity(@"bolt.fill",@"Charging",@"",b>=0?[NSString stringWithFormat:@"%.0f%%",b*100]:nil,RDColor(@"#4ADE80",1),3.2);}gWasCharging=c;}];
    __block BOOL lpm=NSProcessInfo.processInfo.lowPowerModeEnabled;[nc addObserverForName:NSProcessInfoPowerStateDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){BOOL now=NSProcessInfo.processInfo.lowPowerModeEnabled;if(now!=lpm&&RDBool(@"lowPower",YES))RDActivity(now?@"battery.25":@"battery.100",now?@"Low Power Mode":@"Power Normal",@"",nil,now?RDColor(@"#FACC15",1):RDColor(@"#4ADE80",1),2.8);lpm=now;}];
    [nc addObserverForName:UIScreenCapturedDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){BOOL v=UIScreen.mainScreen.isCaptured;if(v!=gRecording&&RDBool(@"recording",YES))RDActivity(v?@"record.circle.fill":@"record.circle",v?@"Screen Recording":@"Recording Stopped",@"",nil,v?RDColor(@"#FB7185",1):UIColor.whiteColor,3.0);gRecording=v;}];
    [nc addObserverForName:UIDeviceOrientationDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){UIDeviceOrientation o=UIDevice.currentDevice.orientation;if(UIDeviceOrientationIsLandscape(o))gLandscape=YES;else if(UIDeviceOrientationIsPortrait(o))gLandscape=NO;RDRender(NO);}];
    // Volume HUD: observe the public AVAudioSession outputVolume property; never change volume.
    AVAudioSession*session=AVAudioSession.sharedInstance; [session addObserver:(id)gIsland forKeyPath:@"outputVolume" options:NSKeyValueObservingOptionNew context:NULL];
    // Call state via public CallKit observer. No call is answered or ended by the tweak.
    CXCallObserver*observer=[CXCallObserver new];static id callHolder;callHolder=observer;[observer setDelegate:(id<CXCallObserverDelegate>)gIsland queue:dispatch_get_main_queue()];objc_setAssociatedObject(gIsland,@selector(setDelegate:queue:),observer,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // Ringer state is observed through the SpringBoard Darwin notification channel.
    notify_register_dispatch("com.apple.springboard.ringerstate",&gRingerToken,dispatch_get_main_queue(),^(int token){uint64_t state=0;notify_get_state(token,&state);if(gRingerState!=UINT64_MAX&&state!=gRingerState&&RDBool(@"ringer",YES)){BOOL silent=(state==0);RDActivity(silent?@"bell.slash.fill":@"bell.fill",silent?@"Silent Mode":@"Ringer On",@"",nil,silent?RDColor(@"#FB923C",1):UIColor.whiteColor,2.4);}gRingerState=state;});
    notify_get_state(gRingerToken,&gRingerState);
    // Timer app notifications vary by iOS release; observe known notification names without hooking methods.
    for(NSString*n in @[@"MTTimerManagerTimersChanged",@"com.apple.mobiletimer.timerfired",@"com.apple.mobiletimer.timerpaused"])[nc addObserverForName:n object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*note){if(RDBool(@"timers",YES))RDActivity(@"timer",@"Timer Updated",@"Open Clock for details",nil,RDColor(@"#60A5FA",1),3.0);}];
}

@interface RDIslandView (RDObservers) <CXCallObserverDelegate>
@end
@implementation RDIslandView (RDObservers)
- (void)observeValueForKeyPath:(NSString*)key ofObject:(id)obj change:(NSDictionary*)change context:(void*)ctx{if([key isEqualToString:@"outputVolume"]&&RDBool(@"volume",YES)){float v=[change[NSKeyValueChangeNewKey] floatValue];RDActivity(@"speaker.wave.2.fill",@"Volume",[NSString stringWithFormat:@"%.0f%%",v*100],nil,UIColor.whiteColor,1.5);}else [super observeValueForKeyPath:key ofObject:obj change:change context:ctx];}
- (void)callObserver:(CXCallObserver*)observer callChanged:(CXCall*)call{if(!RDBool(@"calls",YES))return;NSString*label=call.hasConnected?@"Call in progress":(call.hasEnded?@"Call ended":(call.isOutgoing?@"Outgoing call":@"Incoming call"));RDActivity(@"phone.fill",label,@"",nil,RDColor(@"#4ADE80",1),call.hasEnded?2.5:5.0);}
@end

static void RDPrefsChanged(CFNotificationCenterRef c,void*o,CFStringRef n,const void*obj,CFDictionaryRef info){CFPreferencesAppSynchronize((__bridge CFStringRef)RD_DOMAIN);dispatch_async(dispatch_get_main_queue(),^{RDRender(YES);});}
static BOOL RDGuard(void){if(access("/var/mobile/realisticdynamic_off",F_OK)==0)return NO;NSString*p=@"/var/mobile/Library/Preferences/com.zidaneadam.realisticdynamic.plist";NSDictionary*d=[NSDictionary dictionaryWithContentsOfFile:p];NSNumber*started=d[@"_started"],*stable=d[@"_stable"],*fails=d[@"_fails"];NSInteger count=([started boolValue]&&![stable boolValue])?[fails integerValue]+1:0;if(count>=3){[@"" writeToFile:@"/var/mobile/realisticdynamic_off" atomically:YES encoding:NSUTF8StringEncoding error:nil];return NO;}return YES;}
static void RDStart(void){if(gWindow||!RDGuard())return;CGRect bounds=UIScreen.mainScreen.bounds;gWindow=[[RDWindow alloc]initWithFrame:bounds];gWindow.windowLevel=UIWindowLevelStatusBar+10;gWindow.backgroundColor=UIColor.clearColor;UIViewController*vc=[UIViewController new];vc.view.backgroundColor=UIColor.clearColor;gWindow.rootViewController=vc;gIsland=[RDIslandView new];[vc.view addSubview:gIsland];gWindow.island=gIsland;
    __weak RDIslandView*weak=gIsland;gIsland.tap=^{if(gTransient){gTransient=nil;[gTransientTimer invalidate];RDRender(YES);return;}if(gHasTrack){gExpanded=!gExpanded;RDHaptic();RDRender(YES);if(gExpanded)RDScheduleCollapse();}};
    gIsland.longPress=^{if(gHasTrack&&!gExpanded){gExpanded=YES;RDHaptic();RDRender(YES);RDScheduleCollapse();}};gIsland.swipe=^{if(gTransient){gTransient=nil;[gTransientTimer invalidate];}gExpanded=NO;RDRender(YES);};
    gIsland.play=^{if(MRCommand)MRCommand(RDPlayPause,NULL);};gIsland.next=^{if(MRCommand)MRCommand(RDNext,NULL);};gIsland.previous=^{if(MRCommand)MRCommand(RDPrevious,NULL);};gIsland.seek=^(double f){if(MRSetElapsed&&gDuration>0){MRSetElapsed(f*gDuration);gElapsed=f*gDuration;gStamp=[NSDate date];}RDScheduleCollapse();};
    gWindow.hidden=NO;RDRender(NO);
    void*h=dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",RTLD_LAZY);if(h){MRInfo=dlsym(h,"MRMediaRemoteGetNowPlayingInfo");MRPlaying=dlsym(h,"MRMediaRemoteGetNowPlayingApplicationIsPlaying");MRCommand=dlsym(h,"MRMediaRemoteSendCommand");MRSetElapsed=dlsym(h,"MRMediaRemoteSetElapsedTime");}
    [NSNotificationCenter.defaultCenter addObserverForName:@"kMRMediaRemoteNowPlayingInfoDidChangeNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){RDRefreshMedia();}];[NSNotificationCenter.defaultCenter addObserverForName:@"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification*n){RDRefreshMedia();}];
    RDSetupObservers();RDRefreshMedia();CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,RDPrefsChanged,(__bridge CFStringRef)RD_PREFS_NOTE,NULL,CFNotificationSuspensionBehaviorCoalesce);
}
__attribute__((constructor)) static void RDInit(void){@autoreleasepool{if(![[NSBundle mainBundle].bundleIdentifier isEqualToString:@"com.apple.springboard"])return;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{RDStart();});}}
