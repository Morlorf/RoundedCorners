#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ServiceManagement/ServiceManagement.h>
#import <CoreGraphics/CoreGraphics.h>
#import <dlfcn.h>

typedef NS_OPTIONS(NSUInteger, CornerMask) {
    CornerTL = 1 << 0,
    CornerTR = 1 << 1,
    CornerBL = 1 << 2,
    CornerBR = 1 << 3
};

typedef struct {
    CornerMask mask;
    int isRight;
    int isTop;
} CornerInfo;

static const CornerInfo kCorners[4] = {
    { CornerBL, 0, 0 },
    { CornerBR, 1, 0 },
    { CornerTL, 0, 1 },
    { CornerTR, 1, 1 }
};

static NSString * const kPrefApplyToAll    = @"applyToAllScreens";
static NSString * const kPrefConfigMode    = @"configMode";
static NSString * const kPrefGenericConfig = @"genericConfig";
static NSString * const kPrefMultiConfig   = @"multiConfig";
static NSString * const kPrefLegacyRadius  = @"radius";

static const NSInteger kMinRadius = 8;
static const NSInteger kMaxRadius = 48;
static const NSInteger kDefaultRadius = 23;

static NSString *DisplayUUID(CGDirectDisplayID did) {
    CFUUIDRef uuidRef = CGDisplayCreateUUIDFromDisplayID(did);
    if (!uuidRef) {
        return [NSString stringWithFormat:@"DISPLAY-%u", did];
    }
    CFStringRef strRef = CFUUIDCreateString(kCFAllocatorDefault, uuidRef);
    CFRelease(uuidRef);
    return (__bridge_transfer NSString *)strRef;
}

static NSInteger ClampRadius(NSInteger r) {
    if (r < kMinRadius) return kMinRadius;
    if (r > kMaxRadius) return kMaxRadius;
    return r;
}

static BOOL HasBuiltinScreen(void) {
    for (NSScreen *s in NSScreen.screens) {
        uint32_t did = [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        if (CGDisplayIsBuiltin(did)) return YES;
    }
    return NO;
}

static void PinWindow(NSWindow *w) {
    static int (*conn)(void);
    static int (*create)(int, int, CFDictionaryRef);
    static int (*setLevel)(int, int, int);
    static int (*show)(int, CFArrayRef);
    static int (*add)(int, int, CFArrayRef, int);
    static int space;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY);
        if (!h) return;
        conn = dlsym(h, "SLSMainConnectionID");
        create = dlsym(h, "SLSSpaceCreate");
        setLevel = dlsym(h, "SLSSpaceSetAbsoluteLevel");
        show = dlsym(h, "SLSShowSpaces");
        add = dlsym(h, "SLSSpaceAddWindowsAndRemoveFromSpaces");
        if (!conn || !create || !setLevel || !show || !add) { conn = NULL; return; }
        space = create(conn(), 1, NULL);
        setLevel(conn(), space, 400);
        show(conn(), (__bridge CFArrayRef)@[@(space)]);
    });
    if (!conn) return;
    add(conn(), space, (__bridge CFArrayRef)@[@(w.windowNumber)], 7);
}

@interface ScreenMockupView : NSView <NSViewToolTipOwner>
@property (nonatomic, assign) CornerMask corners;
@property (nonatomic, assign) BOOL isBuiltin;
@property (nonatomic, assign) BOOL displayEnabled;
@property (nonatomic, assign) BOOL interactive;
@property (nonatomic, copy) void (^onCornersChanged)(CornerMask newCorners);
- (NSRect)screenRect;
- (NSRect)tlRect;
- (NSRect)trRect;
- (NSRect)blRect;
- (NSRect)brRect;
@end

@interface CornerAccessibilityElement : NSAccessibilityElement
@property (nonatomic, weak) ScreenMockupView *mockupView;
@property (nonatomic, assign) CornerMask mask;
@property (nonatomic, copy) NSString *cornerTitle;
+ (instancetype)elementWithParent:(ScreenMockupView *)parent mask:(CornerMask)mask title:(NSString *)title;
@end

@implementation CornerAccessibilityElement

+ (instancetype)elementWithParent:(ScreenMockupView *)parent mask:(CornerMask)mask title:(NSString *)title {
    CornerAccessibilityElement *el = [self new];
    el.mockupView = parent;
    el.accessibilityParent = parent;
    el.mask = mask;
    el.cornerTitle = title;
    return el;
}

- (NSRect)accessibilityFrame {
    if (!self.mockupView || !self.mockupView.window) return NSZeroRect;
    NSRect r = NSZeroRect;
    switch (self.mask) {
        case CornerTL: r = [self.mockupView tlRect]; break;
        case CornerTR: r = [self.mockupView trRect]; break;
        case CornerBL: r = [self.mockupView blRect]; break;
        case CornerBR: r = [self.mockupView brRect]; break;
    }
    NSRect winRect = [self.mockupView convertRect:r toView:nil];
    return [self.mockupView.window convertRectToScreen:winRect];
}

- (NSAccessibilityRole)accessibilityRole {
    return NSAccessibilityButtonRole;
}

- (NSString *)accessibilityLabel {
    return self.cornerTitle;
}

- (id)accessibilityValue {
    if (!self.mockupView) return @"";
    return (self.mockupView.corners & self.mask) ? @"Attivo" : @"Disattivo";
}

- (BOOL)accessibilityPerformPress {
    if (!self.mockupView || !self.mockupView.interactive || !self.mockupView.displayEnabled) return NO;
    [[NSHapticFeedbackManager defaultPerformer] performFeedbackPattern:NSHapticFeedbackPatternGeneric
                                                       performanceTime:NSHapticFeedbackPerformanceTimeDefault];
    self.mockupView.corners ^= self.mask;
    [self.mockupView setNeedsDisplay:YES];
    if (self.mockupView.onCornersChanged) {
        self.mockupView.onCornersChanged(self.mockupView.corners);
    }
    return YES;
}

@end

@implementation ScreenMockupView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        _interactive = YES;
        _displayEnabled = YES;
        _corners = CornerTL | CornerTR | CornerBL | CornerBR;
    }
    return self;
}

- (void)setCorners:(CornerMask)corners {
    if (_corners != corners) {
        _corners = corners;
        [self setNeedsDisplay:YES];
    }
}

- (void)setIsBuiltin:(BOOL)isBuiltin {
    if (_isBuiltin != isBuiltin) {
        _isBuiltin = isBuiltin;
        [self.window invalidateCursorRectsForView:self];
        [self setNeedsDisplay:YES];
    }
}

- (void)setDisplayEnabled:(BOOL)displayEnabled {
    if (_displayEnabled != displayEnabled) {
        _displayEnabled = displayEnabled;
        [self.window invalidateCursorRectsForView:self];
        [self setNeedsDisplay:YES];
    }
}

- (void)setInteractive:(BOOL)interactive {
    if (_interactive != interactive) {
        _interactive = interactive;
        [self.window invalidateCursorRectsForView:self];
        [self setNeedsDisplay:YES];
    }
}

- (BOOL)isFlipped {
    return YES;
}

- (BOOL)isAccessibilityElement {
    return YES;
}

- (NSAccessibilityRole)accessibilityRole {
    return NSAccessibilityGroupRole;
}

- (NSString *)accessibilityLabel {
    return @"Anteprima schermo e selezione angoli";
}

- (NSString *)accessibilityHelp {
    return @"Seleziona o deseleziona i singoli angoli da arrotondare";
}

- (id)accessibilityValue {
    return _displayEnabled ? nil : @"Angoli disattivati su questo display";
}

- (NSArray *)accessibilityChildren {
    if (!_displayEnabled) return @[];
    return @[
        [CornerAccessibilityElement elementWithParent:self mask:CornerTL title:@"Angolo superiore sinistro (TL)"],
        [CornerAccessibilityElement elementWithParent:self mask:CornerTR title:@"Angolo superiore destro (TR)"],
        [CornerAccessibilityElement elementWithParent:self mask:CornerBL title:@"Angolo inferiore sinistro (BL)"],
        [CornerAccessibilityElement elementWithParent:self mask:CornerBR title:@"Angolo inferiore destro (BR)"]
    ];
}

- (NSSize)intrinsicContentSize {
    return NSMakeSize(320, 150);
}

- (NSRect)screenRect {
    NSRect b = CGRectInset(self.bounds, 6, 6);
    return CGRectInset(b, 4, 4);
}

- (NSRect)tlRect {
    NSRect s = [self screenRect];
    return NSMakeRect(NSMinX(s) + 6, NSMinY(s) + 6, 36, 22);
}

- (NSRect)trRect {
    NSRect s = [self screenRect];
    return NSMakeRect(NSMaxX(s) - 6 - 36, NSMinY(s) + 6, 36, 22);
}

- (NSRect)blRect {
    NSRect s = [self screenRect];
    return NSMakeRect(NSMinX(s) + 6, NSMaxY(s) - 6 - 22, 36, 22);
}

- (NSRect)brRect {
    NSRect s = [self screenRect];
    return NSMakeRect(NSMaxX(s) - 6 - 36, NSMaxY(s) - 6 - 22, 36, 22);
}

- (void)resetCursorRects {
    [super resetCursorRects];
    [self removeAllToolTips];
    if (!_interactive || !_displayEnabled) return;
    [self addCursorRect:[self tlRect] cursor:NSCursor.pointingHandCursor];
    [self addCursorRect:[self trRect] cursor:NSCursor.pointingHandCursor];
    [self addCursorRect:[self blRect] cursor:NSCursor.pointingHandCursor];
    [self addCursorRect:[self brRect] cursor:NSCursor.pointingHandCursor];
    [self addToolTipRect:[self tlRect] owner:self userData:NULL];
    [self addToolTipRect:[self trRect] owner:self userData:NULL];
    [self addToolTipRect:[self blRect] owner:self userData:NULL];
    [self addToolTipRect:[self brRect] owner:self userData:NULL];
}

- (NSString *)view:(NSView *)view stringForToolTip:(NSToolTipTag)tag point:(NSPoint)point userData:(void *)data {
    (void)view; (void)tag; (void)data;
    if (NSPointInRect(point, [self tlRect])) return @"Angolo superiore sinistro (TL)";
    if (NSPointInRect(point, [self trRect])) return @"Angolo superiore destro (TR)";
    if (NSPointInRect(point, [self blRect])) return @"Angolo inferiore sinistro (BL)";
    if (NSPointInRect(point, [self brRect])) return @"Angolo inferiore destro (BR)";
    return nil;
}

- (void)mouseDown:(NSEvent *)event {
    if (!_interactive || !_displayEnabled) return;
    NSPoint p = [self convertPoint:event.locationInWindow fromView:nil];
    CornerMask toggle = 0;
    if (NSPointInRect(p, [self tlRect])) toggle = CornerTL;
    else if (NSPointInRect(p, [self trRect])) toggle = CornerTR;
    else if (NSPointInRect(p, [self blRect])) toggle = CornerBL;
    else if (NSPointInRect(p, [self brRect])) toggle = CornerBR;

    if (toggle != 0) {
        [[NSHapticFeedbackManager defaultPerformer] performFeedbackPattern:NSHapticFeedbackPatternGeneric
                                                           performanceTime:NSHapticFeedbackPerformanceTimeDefault];
        self.corners ^= toggle;
        [self setNeedsDisplay:YES];
        if (self.onCornersChanged) {
            self.onCornersChanged(self.corners);
        }
    }
}

- (void)drawBadgeWithTitle:(NSString *)title rect:(NSRect)rect active:(BOOL)active {
    NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:5 yRadius:5];
    NSColor *textColor = nil;
    if (active) {
        [NSColor.controlAccentColor setFill];
        [p fill];
        textColor = NSColor.whiteColor;
    } else {
        [[NSColor colorWithCalibratedWhite:0.22 alpha:0.85] setFill];
        [p fill];
        [[NSColor colorWithCalibratedWhite:0.35 alpha:1.0] setStroke];
        p.lineWidth = 1.0;
        [p stroke];
        textColor = [NSColor colorWithCalibratedWhite:0.75 alpha:1.0];
    }

    NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
    style.alignment = NSTextAlignmentCenter;
    NSDictionary *attrs = @{
        NSFontAttributeName: [NSFont systemFontOfSize:11 weight:NSFontWeightBold],
        NSForegroundColorAttributeName: textColor,
        NSParagraphStyleAttributeName: style
    };
    NSSize textSize = [title sizeWithAttributes:attrs];
    NSRect textRect = NSMakeRect(rect.origin.x,
                                 rect.origin.y + (rect.size.height - textSize.height) / 2.0,
                                 rect.size.width,
                                 textSize.height);
    [title drawInRect:textRect withAttributes:attrs];
}

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];

    NSRect s = [self screenRect];
    NSColor *screenBg = _displayEnabled
        ? [NSColor colorWithCalibratedRed:0.10 green:0.12 blue:0.17 alpha:1.0]
        : [NSColor colorWithCalibratedWhite:0.12 alpha:0.6];
    [screenBg setFill];
    NSRectFill(s);

    if (!_displayEnabled) {
        NSString *disabledMsg = @"Angoli disattivati su questo display";
        NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
        style.alignment = NSTextAlignmentCenter;
        NSDictionary *attrs = @{
            NSFontAttributeName: [NSFont systemFontOfSize:12 weight:NSFontWeightMedium],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:0.70 alpha:0.9],
            NSParagraphStyleAttributeName: style
        };
        NSSize msgSize = [disabledMsg sizeWithAttributes:attrs];
        NSRect msgRect = NSMakeRect(NSMinX(s),
                                    NSMinY(s) + (NSHeight(s) - msgSize.height) / 2.0,
                                    NSWidth(s),
                                    msgSize.height);
        [disabledMsg drawInRect:msgRect withAttributes:attrs];
        return;
    }

    [self drawBadgeWithTitle:@"TL" rect:[self tlRect] active:(self.corners & CornerTL) != 0];
    [self drawBadgeWithTitle:@"TR" rect:[self trRect] active:(self.corners & CornerTR) != 0];
    [self drawBadgeWithTitle:@"BL" rect:[self blRect] active:(self.corners & CornerBL) != 0];
    [self drawBadgeWithTitle:@"BR" rect:[self brRect] active:(self.corners & CornerBR) != 0];
}


@end

@interface PrefsWindow : NSWindow
@end

@implementation PrefsWindow
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (event.keyCode == 53) {
        [self performClose:nil];
        return YES;
    }
    if ((event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask) == NSEventModifierFlagCommand) {
        NSString *chars = event.charactersIgnoringModifiers;
        if ([chars isEqualToString:@"w"] || [chars isEqualToString:@"."]) {
            [self performClose:nil];
            return YES;
        }
        if ([chars isEqualToString:@","]) {
            [self makeKeyAndOrderFront:nil];
            return YES;
        }
    }
    return [super performKeyEquivalent:event];
}

- (void)cancelOperation:(id)sender {
    [self performClose:sender];
}
@end

@interface D : NSObject <NSApplicationDelegate, NSWindowDelegate>
@end

@implementation D {
    NSMutableArray<NSWindow *> *_wins;
    NSWindow *_prefs;
    NSString *_layout;

    NSButton *_applyToAllCheckbox;
    NSTextField *_dispLabel;
    NSPopUpButton *_displayPopup;
    NSTextField *_displaySwitchLabel;
    NSSwitch *_displaySwitch;
    ScreenMockupView *_mockup;
    NSTextField *_sliderLabel;
    NSSlider *_slider;
    NSTextField *_hintLabel;
    NSString *_selectedDisplayUUID;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _wins = [NSMutableArray new];
    }
    return self;
}

#pragma mark - Model & Persistence

- (BOOL)applyToAllScreens {
    id val = [NSUserDefaults.standardUserDefaults objectForKey:kPrefApplyToAll];
    if (val != nil) {
        return [val boolValue];
    }
    NSString *mode = [NSUserDefaults.standardUserDefaults stringForKey:kPrefConfigMode];
    if ([mode isEqualToString:@"multi"] || [mode isEqualToString:@"macbook"]) {
        return NO;
    }
    return YES;
}

- (void)setApplyToAllScreens:(BOOL)applyToAll {
    [NSUserDefaults.standardUserDefaults setBool:applyToAll forKey:kPrefApplyToAll];
    [NSUserDefaults.standardUserDefaults setObject:(applyToAll ? @"generic" : @"multi") forKey:kPrefConfigMode];
}

- (NSDictionary *)genericConfig {
    NSDictionary *d = [NSUserDefaults.standardUserDefaults dictionaryForKey:kPrefGenericConfig];
    if (!d || !d[@"radius"] || !d[@"corners"]) {
        NSMutableDictionary *mut = d ? [d mutableCopy] : [NSMutableDictionary new];
        if (!mut[@"radius"]) {
            NSInteger defaultRadius = kDefaultRadius;
            NSInteger legacy = [NSUserDefaults.standardUserDefaults integerForKey:kPrefLegacyRadius];
            if (legacy > 0) defaultRadius = legacy;
            mut[@"radius"] = @(defaultRadius);
        }
        if (!mut[@"corners"]) {
            mut[@"corners"] = @(CornerTL | CornerTR | CornerBL | CornerBR);
        }
        if (!mut[@"targetMode"]) mut[@"targetMode"] = @"all";
        if (!mut[@"selectedUUID"]) mut[@"selectedUUID"] = @"";
        [NSUserDefaults.standardUserDefaults setObject:mut forKey:kPrefGenericConfig];
        return mut;
    }
    return d;
}

- (void)setGenericConfig:(NSDictionary *)d {
    [NSUserDefaults.standardUserDefaults setObject:d forKey:kPrefGenericConfig];
}

- (NSDictionary<NSString *, NSDictionary *> *)multiConfig {
    NSDictionary *d = [NSUserDefaults.standardUserDefaults dictionaryForKey:kPrefMultiConfig];
    return d ? d : @{};
}

- (void)setMultiConfig:(NSDictionary<NSString *, NSDictionary *> *)d {
    [NSUserDefaults.standardUserDefaults setObject:d forKey:kPrefMultiConfig];
}

- (NSScreen *)screenForUUID:(NSString *)uuid {
    if (!uuid) return nil;
    for (NSScreen *s in NSScreen.screens) {
        uint32_t did = [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        if ([DisplayUUID(did) isEqualToString:uuid]) {
            return s;
        }
    }
    return nil;
}

- (NSMutableDictionary *)ensureConfigForScreenUUID:(NSString *)uuid {
    NSDictionary *mc = [self multiConfig];
    NSDictionary *entry = uuid ? mc[uuid] : nil;
    CornerMask defaultCorners = CornerTL | CornerTR | CornerBL | CornerBR;

    NSMutableDictionary *newEntry = entry ? [entry mutableCopy] : [NSMutableDictionary new];
    BOOL modified = NO;
    if (newEntry[@"enabled"] == nil) {
        newEntry[@"enabled"] = @YES;
        modified = YES;
    }
    if (!newEntry[@"radius"]) {
        NSInteger initRadius = kDefaultRadius;
        NSDictionary *gc = [NSUserDefaults.standardUserDefaults dictionaryForKey:kPrefGenericConfig];
        if (gc && gc[@"radius"]) {
            initRadius = [gc[@"radius"] integerValue];
        }
        newEntry[@"radius"] = @(initRadius);
        modified = YES;
    }
    if (!newEntry[@"corners"]) {
        newEntry[@"corners"] = @(defaultCorners);
        modified = YES;
    }
    if (uuid && (modified || !mc[uuid])) {
        NSMutableDictionary *mut = [mc mutableCopy];
        mut[uuid] = newEntry;
        [self setMultiConfig:mut];
    }
    return newEntry;
}

- (NSDictionary *)configForScreenUUID:(NSString *)uuid {
    return [self ensureConfigForScreenUUID:uuid];
}

- (void)migrateLegacyConfigIfNeeded {
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    if (![ud stringForKey:kPrefConfigMode] && [ud objectForKey:kPrefLegacyRadius]) {
        NSInteger oldRadius = [ud integerForKey:kPrefLegacyRadius];
        if (oldRadius > 0) {
            if (HasBuiltinScreen()) {
                [ud setObject:@"macbook" forKey:kPrefConfigMode];
                [ud setBool:NO forKey:kPrefApplyToAll];
            } else {
                [ud setObject:@"generic" forKey:kPrefConfigMode];
                [ud setBool:YES forKey:kPrefApplyToAll];
                [ud setObject:@{
                    @"targetMode": @"all",
                    @"selectedUUID": @"",
                    @"radius": @(oldRadius),
                    @"corners": @(CornerTL | CornerTR | CornerBL | CornerBR)
                } forKey:kPrefGenericConfig];
            }
        }
    }
    if (![ud boolForKey:@"v2_radius_23_migrated"]) {
        [ud setBool:YES forKey:@"v2_radius_23_migrated"];
        NSDictionary *gc = [ud dictionaryForKey:kPrefGenericConfig];
        if (gc && [gc[@"radius"] integerValue] == 24) {
            NSMutableDictionary *mut = [gc mutableCopy];
            mut[@"radius"] = @(kDefaultRadius);
            [ud setObject:mut forKey:kPrefGenericConfig];
        }
        NSDictionary *mc = [ud dictionaryForKey:kPrefMultiConfig];
        if (mc) {
            NSMutableDictionary *mutMC = [mc mutableCopy];
            BOOL changed = NO;
            for (NSString *key in mc) {
                NSDictionary *entry = mc[key];
                if ([entry isKindOfClass:[NSDictionary class]] && [entry[@"radius"] integerValue] == 24) {
                    NSMutableDictionary *mutEntry = [entry mutableCopy];
                    mutEntry[@"radius"] = @(kDefaultRadius);
                    mutMC[key] = mutEntry;
                    changed = YES;
                }
            }
            if (changed) {
                [ud setObject:mutMC forKey:kPrefMultiConfig];
            }
        }
    }
}

#pragma mark - App Lifecycle

- (void)applicationDidFinishLaunching:(NSNotification *)n {
    (void)n;
    if (!_wins) _wins = [NSMutableArray new];
    [self buildMenu];
    [self migrateLegacyConfigIfNeeded];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screensChanged)
        name:NSApplicationDidChangeScreenParametersNotification object:nil];
    [self rebuild];

    NSAppleEventDescriptor *ev = NSAppleEventManager.sharedAppleEventManager.currentAppleEvent;
    BOOL atLogin = [[ev paramDescriptorForKeyword:'prdt'] enumCodeValue] == 'lgit';

    if (!atLogin) {
        [self showPrefs];
    }
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)a hasVisibleWindows:(BOOL)f {
    (void)a;
    (void)f;
    [self showPrefs];
    return NO;
}

- (void)windowWillClose:(NSNotification *)notification {
    if (notification.object == _prefs) {
        @autoreleasepool {
            _prefs.contentViewController = nil;
            _prefs.contentView = nil;
            _prefs.delegate = nil;
            _prefs = nil;
            _applyToAllCheckbox = nil;
            _dispLabel = nil;
            _displayPopup = nil;
            _displaySwitchLabel = nil;
            _displaySwitch = nil;
            _mockup = nil;
            _sliderLabel = nil;
            _slider = nil;
            _hintLabel = nil;
            _selectedDisplayUUID = nil;
        }
    }
}

- (void)buildMenu {
    NSMenu *bar = [NSMenu new], *app = [NSMenu new];
    NSMenuItem *aboutItem = [app addItemWithTitle:@"Informazioni su Rounded Corners" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    aboutItem.target = NSApp;
    [app addItem:[NSMenuItem separatorItem]];
    NSMenuItem *settingsItem = [app addItemWithTitle:@"Impostazioni…" action:@selector(showPrefs) keyEquivalent:@","];
    settingsItem.target = self;
    [app addItem:[NSMenuItem separatorItem]];
    NSMenuItem *quitItem = [app addItemWithTitle:@"Esci da Rounded Corners" action:@selector(terminate:) keyEquivalent:@"q"];
    quitItem.target = NSApp;
    [bar addItemWithTitle:@"" action:nil keyEquivalent:@""].submenu = app;

    NSMenu *fileMenu = [NSMenu new];
    [fileMenu addItemWithTitle:@"Chiudi finestra" action:@selector(performClose:) keyEquivalent:@"w"];
    [bar addItemWithTitle:@"File" action:nil keyEquivalent:@""].submenu = fileMenu;

    NSApp.mainMenu = bar;
}

#pragma mark - Geometry & Mask Construction

- (void)createCornersForScreen:(NSScreen *)s radius:(CGFloat)r corners:(CornerMask)activeCorners {
    if (r <= 0 || activeCorners == 0) return;
    uint32_t did = [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
    if (CGDisplayIsBuiltin(did) && r <= (CGFloat)kDefaultRadius) {
        activeCorners &= (CornerBL | CornerBR);
    }
    if (activeCorners == 0) return;
    NSRect f = s.frame;
    for (int i = 0; i < 4; i++) {
        if (!(activeCorners & kCorners[i].mask)) continue;
        CGFloat x = kCorners[i].isRight ? (NSMaxX(f) - r) : f.origin.x;
        CGFloat y = kCorners[i].isTop   ? (NSMaxY(f) - r) : f.origin.y;
        NSRect rect = NSMakeRect(x, y, r, r);
        CGRect ellipseRect = CGRectMake(
            kCorners[i].isRight ? -r : 0,
            kCorners[i].isTop   ? -r : 0,
            2 * r,
            2 * r
        );

        NSPanel *w = [[NSPanel alloc] initWithContentRect:rect
            styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel
            backing:NSBackingStoreBuffered defer:NO];
        w.releasedWhenClosed = NO;
        w.floatingPanel = YES;
        w.hidesOnDeactivate = NO;
        w.opaque = NO;
        w.backgroundColor = NSColor.clearColor;
        w.hasShadow = NO;
        w.ignoresMouseEvents = YES;
        w.sharingType = NSWindowSharingNone;
        w.level = NSScreenSaverWindowLevel;
        w.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                               NSWindowCollectionBehaviorStationary |
                               NSWindowCollectionBehaviorIgnoresCycle |
                               NSWindowCollectionBehaviorFullScreenAuxiliary;

        NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, r, r)];
        v.wantsLayer = YES;
        CAShapeLayer *l = [CAShapeLayer layer];
        CGMutablePathRef p = CGPathCreateMutable();
        CGPathAddRect(p, NULL, CGRectMake(0, 0, r, r));
        CGPathAddEllipseInRect(p, NULL, ellipseRect);
        l.path = p;
        CGPathRelease(p);
        l.fillRule = kCAFillRuleEvenOdd;
        l.fillColor = NSColor.blackColor.CGColor;
        l.frame = CGRectMake(0, 0, r, r);
        [v.layer addSublayer:l];

        w.contentView = v;
        [w setFrame:rect display:NO];
        [w orderFrontRegardless];
        PinWindow(w);
        [_wins addObject:w];
    }
}

- (void)screensChanged {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(onScreensChangedDebounced) object:nil];
    [self performSelector:@selector(onScreensChangedDebounced) withObject:nil afterDelay:0.3];
}

- (void)onScreensChangedDebounced {
    [self rebuild];
    if (_prefs && _prefs.isVisible) {
        [self updateUI];
    }
}

- (void)invalidateLayoutAndRebuild {
    _layout = nil;
    [self rebuild];
}

- (void)rebuild {
    BOOL applyToAll = [self applyToAllScreens];
    NSMutableString *layout = [NSMutableString stringWithFormat:@"mode:%@", applyToAll ? @"all" : @"multi"];
    if (applyToAll) {
        NSDictionary *gc = [self genericConfig];
        NSInteger r = [gc[@"radius"] integerValue];
        NSUInteger corners = [gc[@"corners"] unsignedIntegerValue];
        [layout appendFormat:@":%ld:%lu", (long)r, (unsigned long)corners];
        for (NSScreen *s in NSScreen.screens) {
            uint32_t did = [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
            [layout appendFormat:@":%u:%@:%f", did, NSStringFromRect(s.frame), s.backingScaleFactor];
        }
    } else {
        for (NSScreen *s in NSScreen.screens) {
            uint32_t did = [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
            NSString *uuid = DisplayUUID(did);
            NSDictionary *entry = [self configForScreenUUID:uuid];
            [layout appendFormat:@":%@:%@:%@:%@:%@:%f", uuid, entry[@"enabled"], entry[@"radius"], entry[@"corners"], NSStringFromRect(s.frame), s.backingScaleFactor];
        }
    }

    if ([layout isEqualToString:_layout]) return;
    _layout = layout;

    for (NSWindow *w in _wins) [w close];
    [_wins removeAllObjects];

    if (applyToAll) {
        NSDictionary *gc = [self genericConfig];
        NSInteger r = ClampRadius([gc[@"radius"] integerValue]);
        NSUInteger corners = [gc[@"corners"] unsignedIntegerValue];
        for (NSScreen *s in NSScreen.screens) {
            uint32_t did = [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
            CornerMask activeCorners = (CornerMask)corners;
            if (CGDisplayIsBuiltin(did) && r <= kDefaultRadius) {
                activeCorners &= (CornerBL | CornerBR);
            }
            [self createCornersForScreen:s radius:r corners:activeCorners];
        }
    } else {
        for (NSScreen *s in NSScreen.screens) {
            uint32_t did = [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
            NSString *uuid = DisplayUUID(did);
            NSDictionary *entry = [self configForScreenUUID:uuid];
            if (![entry[@"enabled"] boolValue]) {
                continue;
            }
            NSInteger r = ClampRadius([entry[@"radius"] integerValue]);
            CornerMask corners = (CornerMask)[entry[@"corners"] unsignedIntegerValue];
            if (CGDisplayIsBuiltin(did) && r <= kDefaultRadius) {
                corners &= (CornerBL | CornerBR);
            }
            [self createCornersForScreen:s radius:r corners:corners];
        }
    }
}

#pragma mark - Window & View Presentation

- (void)ensurePrefsWindow {
    if (!_prefs) {
        _prefs = [[PrefsWindow alloc] initWithContentRect:NSMakeRect(0, 0, 480, 440)
            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
            backing:NSBackingStoreBuffered
            defer:NO];
        _prefs.title = @"Rounded Corners";
        _prefs.identifier = @"PreferencesWindow";
        _prefs.tabbingMode = NSWindowTabbingModeDisallowed;
        _prefs.releasedWhenClosed = NO;
        _prefs.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace | NSWindowCollectionBehaviorFullScreenAuxiliary;
        _prefs.delegate = self;
        [_prefs center];
    }
}

- (void)switchToView:(NSView *)view contentSize:(NSSize)size {
    BOOL wasVisible = _prefs.isVisible;
    _prefs.contentView = view;
    if (wasVisible) {
        NSRect contentRect = NSMakeRect(_prefs.frame.origin.x, _prefs.frame.origin.y, size.width, size.height);
        NSRect frame = [_prefs frameRectForContentRect:contentRect];
        frame.origin.y = NSMaxY(_prefs.frame) - frame.size.height;
        if (!NSEqualRects(_prefs.frame, frame)) {
            [_prefs setFrame:frame display:YES animate:YES];
        }
    } else {
        [_prefs setContentSize:size];
        [_prefs center];
    }
}

- (void)showPrefs {
    [self ensurePrefsWindow];
    if (!_mockup) {
        NSView *v = [self createPrefsView];
        [self switchToView:v contentSize:NSMakeSize(480, 440)];
    }
    _prefs.initialFirstResponder = _applyToAllCheckbox;
    [self updateUI];
    [_prefs makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (NSView *)createPrefsView {
    NSView *container = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 480, 440)];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [container.widthAnchor constraintEqualToConstant:480].active = YES;

    NSStackView *st = [NSStackView new];
    st.orientation = NSUserInterfaceLayoutOrientationVertical;
    st.alignment = NSLayoutAttributeLeading;
    st.spacing = 11;
    st.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:st];

    NSLayoutConstraint *bottomC = [st.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-16];
    bottomC.priority = NSLayoutPriorityDefaultLow;

    [NSLayoutConstraint activateConstraints:@[
        [st.topAnchor constraintEqualToAnchor:container.topAnchor constant:16],
        [st.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:24],
        [st.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-24],
        bottomC
    ]];

    // 1. Header row
    NSStackView *topRow = [NSStackView new];
    topRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    topRow.alignment = NSLayoutAttributeCenterY;
    topRow.spacing = 10;

    NSImageView *iconView = [NSImageView new];
    iconView.imageScaling = NSImageScaleProportionallyUpOrDown;
    NSImage *appIcon = [NSImage imageNamed:NSImageNameApplicationIcon];
    if (!appIcon || appIcon.size.width == 0) {
        appIcon = [NSWorkspace.sharedWorkspace iconForFile:NSBundle.mainBundle.bundlePath];
    }
    iconView.image = appIcon;
    iconView.accessibilityRole = NSAccessibilityImageRole;
    iconView.accessibilityLabel = @"Icona dell'applicazione Rounded Corners";
    [iconView.widthAnchor constraintEqualToConstant:24].active = YES;
    [iconView.heightAnchor constraintEqualToConstant:24].active = YES;
    [topRow addArrangedSubview:iconView];

    NSTextField *title = [NSTextField labelWithString:@"Rounded Corners"];
    title.font = [NSFont systemFontOfSize:15 weight:NSFontWeightBold];
    title.textColor = NSColor.labelColor;
    title.accessibilityRole = NSAccessibilityStaticTextRole;
    [topRow addArrangedSubview:title];

    NSView *spacer1 = [NSView new];
    [spacer1 setContentHuggingPriority:NSLayoutPriorityFittingSizeCompression forOrientation:NSLayoutConstraintOrientationHorizontal];
    [topRow addArrangedSubview:spacer1];

    NSButton *login = [NSButton checkboxWithTitle:@"Avvia al login" target:self action:@selector(loginChanged:)];
    login.state = (SMAppService.mainAppService.status == SMAppServiceStatusEnabled) ? NSControlStateValueOn : NSControlStateValueOff;
    login.font = [NSFont systemFontOfSize:12];
    login.accessibilityLabel = @"Avvia al login";
    login.accessibilityHelp = @"Esegui automaticamente Rounded Corners all'accesso dell'utente";
    login.accessibilityRole = NSAccessibilityCheckBoxRole;
    [topRow addArrangedSubview:login];

    [st addArrangedSubview:topRow];
    [topRow.widthAnchor constraintEqualToAnchor:st.widthAnchor].active = YES;

    NSBox *sep1 = [NSBox new];
    sep1.boxType = NSBoxSeparator;
    [st addArrangedSubview:sep1];
    [sep1.widthAnchor constraintEqualToAnchor:st.widthAnchor].active = YES;

    // 2. Global Checkbox
    _applyToAllCheckbox = [NSButton checkboxWithTitle:@"Applica le stesse impostazioni a tutti i monitor"
                                               target:self
                                               action:@selector(onApplyToAllChanged:)];
    _applyToAllCheckbox.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    _applyToAllCheckbox.accessibilityLabel = @"Applica le stesse impostazioni a tutti i monitor";
    _applyToAllCheckbox.accessibilityHelp = @"Sincronizza le opzioni di curvatura e raggio su tutti gli schermi connessi";
    _applyToAllCheckbox.accessibilityRole = NSAccessibilityCheckBoxRole;
    [st addArrangedSubview:_applyToAllCheckbox];
    [_applyToAllCheckbox.leadingAnchor constraintEqualToAnchor:st.leadingAnchor].active = YES;

    // 3. Display Selection Row
    NSStackView *dispRow = [NSStackView new];
    dispRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    dispRow.alignment = NSLayoutAttributeCenterY;
    dispRow.spacing = 10;

    _dispLabel = [NSTextField labelWithString:@"Display:"];
    _dispLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
    _dispLabel.textColor = NSColor.labelColor;
    _dispLabel.accessibilityRole = NSAccessibilityStaticTextRole;
    [dispRow addArrangedSubview:_dispLabel];

    _displayPopup = [NSPopUpButton new];
    _displayPopup.pullsDown = NO;
    _displayPopup.autoenablesItems = NO;
    _displayPopup.target = self;
    _displayPopup.action = @selector(onDisplayPopupChanged:);
    _displayPopup.font = [NSFont systemFontOfSize:12];
    _displayPopup.lineBreakMode = NSLineBreakByTruncatingTail;
    [_displayPopup setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    _displayPopup.accessibilityLabel = @"Selezione monitor";
    _displayPopup.accessibilityHelp = @"Scegli il display da configurare individualmente";
    _displayPopup.accessibilityRole = NSAccessibilityPopUpButtonRole;
    [_displayPopup.widthAnchor constraintGreaterThanOrEqualToConstant:200].active = YES;
    [dispRow addArrangedSubview:_displayPopup];

    NSView *dispSpacer = [NSView new];
    [dispSpacer setContentHuggingPriority:NSLayoutPriorityFittingSizeCompression forOrientation:NSLayoutConstraintOrientationHorizontal];
    [dispRow addArrangedSubview:dispSpacer];

    _displaySwitchLabel = [NSTextField labelWithString:@"Abilita:"];
    _displaySwitchLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
    _displaySwitchLabel.textColor = NSColor.labelColor;
    _displaySwitchLabel.accessibilityRole = NSAccessibilityStaticTextRole;
    [dispRow addArrangedSubview:_displaySwitchLabel];

    _displaySwitch = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    _displaySwitch.target = self;
    _displaySwitch.action = @selector(onDisplaySwitchChanged:);
    _displaySwitch.accessibilityLabel = @"Attiva angoli su questo display";
    _displaySwitch.accessibilityHelp = @"Attiva o disattiva gli angoli arrotondati per il monitor selezionato";
    [dispRow addArrangedSubview:_displaySwitch];

    [st addArrangedSubview:dispRow];
    [dispRow.widthAnchor constraintEqualToAnchor:st.widthAnchor].active = YES;

    // 4. Mockup View
    _mockup = [[ScreenMockupView alloc] initWithFrame:NSMakeRect(0, 0, 432, 145)];
    __weak typeof(self) weakSelf = self;
    _mockup.onCornersChanged = ^(CornerMask newCorners) {
        [weakSelf onMockupCornersChanged:newCorners];
    };
    [st addArrangedSubview:_mockup];
    [_mockup.widthAnchor constraintEqualToAnchor:st.widthAnchor].active = YES;
    [_mockup.heightAnchor constraintEqualToConstant:145].active = YES;

    // 5. Slider and Label
    _sliderLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"Raggio: %ld pt", (long)kDefaultRadius]];
    _sliderLabel.font = [NSFont systemFontOfSize:12 weight:NSFontWeightSemibold];
    _sliderLabel.textColor = NSColor.labelColor;
    _sliderLabel.accessibilityRole = NSAccessibilityStaticTextRole;
    [st addArrangedSubview:_sliderLabel];
    [_sliderLabel.leadingAnchor constraintEqualToAnchor:st.leadingAnchor].active = YES;

    _slider = [NSSlider sliderWithValue:kDefaultRadius minValue:kMinRadius maxValue:kMaxRadius target:self action:@selector(onSliderChanged:)];
    _slider.numberOfTickMarks = 9;
    _slider.allowsTickMarkValuesOnly = NO;
    _slider.tickMarkPosition = NSTickMarkPositionBelow;
    _slider.accessibilityLabel = @"Raggio degli angoli";
    _slider.accessibilityHelp = @"Regola il raggio di curvatura degli angoli in punti";
    _slider.accessibilityRole = NSAccessibilitySliderRole;
    _slider.accessibilityMinValue = @(kMinRadius);
    _slider.accessibilityMaxValue = @(kMaxRadius);
    _slider.accessibilityValueDescription = [NSString stringWithFormat:@"%ld pt", (long)kDefaultRadius];
    [st addArrangedSubview:_slider];
    [_slider.widthAnchor constraintEqualToAnchor:st.widthAnchor].active = YES;

    _hintLabel = [NSTextField labelWithString:@""];
    _hintLabel.font = [NSFont systemFontOfSize:11];
    _hintLabel.textColor = NSColor.secondaryLabelColor;
    _hintLabel.lineBreakMode = NSLineBreakByWordWrapping;
    _hintLabel.maximumNumberOfLines = 3;
    _hintLabel.preferredMaxLayoutWidth = 432;
    _hintLabel.accessibilityRole = NSAccessibilityStaticTextRole;
    [st addArrangedSubview:_hintLabel];
    [_hintLabel.widthAnchor constraintEqualToAnchor:st.widthAnchor].active = YES;

    // 6. Separator
    NSBox *sep2 = [NSBox new];
    sep2.boxType = NSBoxSeparator;
    [st addArrangedSubview:sep2];
    [sep2.widthAnchor constraintEqualToAnchor:st.widthAnchor].active = YES;

    // 7. Footer
    NSStackView *footer = [NSStackView new];
    footer.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    footer.alignment = NSLayoutAttributeCenterY;

    NSString *appVer = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"1.0";
    NSTextField *verLabel = [NSTextField labelWithString:[NSString stringWithFormat:@"v%@", appVer]];
    verLabel.font = [NSFont systemFontOfSize:11];
    verLabel.textColor = NSColor.tertiaryLabelColor;
    verLabel.accessibilityRole = NSAccessibilityStaticTextRole;
    verLabel.accessibilityLabel = [NSString stringWithFormat:@"Versione %@", verLabel.stringValue];
    [footer addArrangedSubview:verLabel];

    NSView *spacer2 = [NSView new];
    [spacer2 setContentHuggingPriority:NSLayoutPriorityFittingSizeCompression forOrientation:NSLayoutConstraintOrientationHorizontal];
    [footer addArrangedSubview:spacer2];

    NSButton *quitBtn = [NSButton buttonWithTitle:@"Esci da Rounded Corners" target:NSApp action:@selector(terminate:)];
    quitBtn.bezelStyle = NSBezelStyleRounded;
    quitBtn.controlSize = NSControlSizeRegular;
    quitBtn.font = [NSFont systemFontOfSize:[NSFont systemFontSizeForControlSize:NSControlSizeRegular]];
    quitBtn.accessibilityLabel = @"Esci da Rounded Corners";
    quitBtn.accessibilityHelp = @"Chiude l'applicazione Rounded Corners";
    quitBtn.accessibilityRole = NSAccessibilityButtonRole;
    [footer addArrangedSubview:quitBtn];

    [st addArrangedSubview:footer];
    [footer.widthAnchor constraintEqualToAnchor:st.widthAnchor].active = YES;

    // Full Keyboard Access nextKeyView chain
    login.nextKeyView = _applyToAllCheckbox;
    _applyToAllCheckbox.nextKeyView = _displayPopup;
    _displayPopup.nextKeyView = _displaySwitch;
    _displaySwitch.nextKeyView = _slider;
    _slider.nextKeyView = quitBtn;
    quitBtn.nextKeyView = login;

    return container;
}

- (void)updateUI {
    if (!_prefs || !_prefs.contentView) return;

    BOOL applyToAll = [self applyToAllScreens];
    _applyToAllCheckbox.state = applyToAll ? NSControlStateValueOn : NSControlStateValueOff;

    NSArray<NSScreen *> *screens = NSScreen.screens;
    NSScreen *selectedScreen = nil;
    if (_selectedDisplayUUID) {
        for (NSScreen *s in screens) {
            uint32_t did = [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
            if ([DisplayUUID(did) isEqualToString:_selectedDisplayUUID]) {
                selectedScreen = s;
                break;
            }
        }
    }
    if (!selectedScreen && screens.count > 0) {
        selectedScreen = screens.firstObject;
        uint32_t did = [selectedScreen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        _selectedDisplayUUID = DisplayUUID(did);
    }

    [_displayPopup removeAllItems];

    if (screens.count == 0) {
        NSMenuItem *noneItem = [[NSMenuItem alloc] initWithTitle:@"Nessun display" action:NULL keyEquivalent:@""];
        [_displayPopup.menu addItem:noneItem];
        _displayPopup.enabled = NO;
        if (_dispLabel) _dispLabel.textColor = NSColor.disabledControlTextColor;
        _displaySwitch.enabled = NO;
        _displaySwitch.state = NSControlStateValueOff;
        if (_displaySwitchLabel) _displaySwitchLabel.textColor = NSColor.disabledControlTextColor;
        _mockup.displayEnabled = NO;
        _slider.enabled = NO;
        _sliderLabel.stringValue = @"Nessun monitor rilevato";
        _sliderLabel.textColor = NSColor.disabledControlTextColor;
        if (_hintLabel) _hintLabel.stringValue = @"";
        return;
    }

    if (applyToAll) {
        NSMenuItem *allItem = [[NSMenuItem alloc] initWithTitle:@"Tutti i monitor connessi" action:NULL keyEquivalent:@""];
        [_displayPopup.menu addItem:allItem];
        _displayPopup.enabled = NO;
        if (_dispLabel) _dispLabel.textColor = NSColor.disabledControlTextColor;
        _displaySwitch.enabled = NO;
        _displaySwitch.state = NSControlStateValueOn;
        if (_displaySwitchLabel) _displaySwitchLabel.textColor = NSColor.disabledControlTextColor;

        NSDictionary *gc = [self genericConfig];
        NSInteger r = ClampRadius([gc[@"radius"] integerValue]);
        NSUInteger corners = [gc[@"corners"] unsignedIntegerValue];

        _mockup.isBuiltin = (screens.count == 1 && HasBuiltinScreen());
        _mockup.displayEnabled = YES;
        _mockup.corners = corners;

        _slider.enabled = YES;
        _slider.integerValue = r;
        _slider.accessibilityValueDescription = [NSString stringWithFormat:@"%ld pt", (long)r];
        _sliderLabel.stringValue = [NSString stringWithFormat:@"Raggio: %ld pt", (long)r];
        _sliderLabel.textColor = NSColor.labelColor;
    } else {
        _displayPopup.enabled = YES;
        if (_dispLabel) _dispLabel.textColor = NSColor.labelColor;
        _displaySwitch.enabled = YES;
        if (_displaySwitchLabel) _displaySwitchLabel.textColor = NSColor.labelColor;

        NSInteger externalCount = 0;
        for (NSScreen *s in screens) {
            uint32_t did = [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
            if (!CGDisplayIsBuiltin(did)) externalCount++;
        }

        NSInteger selectedIdx = 0;
        NSInteger externalIndex = 0;
        for (NSInteger i = 0; i < (NSInteger)screens.count; i++) {
            NSScreen *s = screens[i];
            uint32_t did = [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
            NSString *uuid = DisplayUUID(did);
            BOOL isBuiltin = CGDisplayIsBuiltin(did);
            NSString *icon = isBuiltin ? @"💻" : @"🖥️";
            NSString *name = s.localizedName.length > 0 ? s.localizedName : @"Display";
            NSString *typeStr;
            if (isBuiltin) {
                typeStr = @"Integrato";
            } else {
                externalIndex++;
                if (externalCount > 1) {
                    typeStr = [NSString stringWithFormat:@"Esterno %ld", (long)externalIndex];
                } else {
                    typeStr = @"Esterno";
                }
            }
            NSString *itemTitle = [NSString stringWithFormat:@"%@ %@ (%@)", icon, name, typeStr];
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:itemTitle action:NULL keyEquivalent:@""];
            item.representedObject = uuid;
            [_displayPopup.menu addItem:item];

            if ([uuid isEqualToString:_selectedDisplayUUID]) {
                selectedIdx = i;
            }
        }
        if (selectedIdx >= 0 && selectedIdx < _displayPopup.numberOfItems) {
            [_displayPopup selectItemAtIndex:selectedIdx];
        }

        if (selectedScreen) {
            uint32_t did = [selectedScreen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
            BOOL isBuiltin = CGDisplayIsBuiltin(did);
            NSDictionary *cfg = [self configForScreenUUID:_selectedDisplayUUID];
            BOOL enabled = [cfg[@"enabled"] boolValue];
            NSInteger r = ClampRadius([cfg[@"radius"] integerValue]);
            NSUInteger corners = [cfg[@"corners"] unsignedIntegerValue];

            _displaySwitch.state = enabled ? NSControlStateValueOn : NSControlStateValueOff;

            _mockup.isBuiltin = isBuiltin;
            _mockup.displayEnabled = enabled;
            _mockup.corners = corners;

            _slider.enabled = enabled;
            _slider.integerValue = r;
            _slider.accessibilityValueDescription = [NSString stringWithFormat:@"%ld pt", (long)r];
            if (enabled) {
                _sliderLabel.stringValue = [NSString stringWithFormat:@"Raggio: %ld pt", (long)r];
                _sliderLabel.textColor = NSColor.labelColor;
            } else {
                _sliderLabel.stringValue = [NSString stringWithFormat:@"Raggio memorizzato: %ld pt (inattivo)", (long)r];
                _sliderLabel.textColor = NSColor.secondaryLabelColor;
            }
        }
    }
    [self updateHintLabel];
}

- (void)updateHintLabel {
    if (!_hintLabel) return;
    BOOL applyToAll = [self applyToAllScreens];
    if (applyToAll) {
        NSDictionary *gc = [self genericConfig];
        NSInteger r = [gc[@"radius"] integerValue];
        if (HasBuiltinScreen()) {
            if (r <= kDefaultRadius) {
                _hintLabel.stringValue = @"Sui display Mac compatibili, gli angoli superiori vengono disegnati solo per raggi superiori a 23 pt.";
            } else {
                _hintLabel.stringValue = @"Raggio superiore a 23 pt: gli angoli superiori verranno disegnati anche sui display Mac compatibili.";
            }
        } else {
            _hintLabel.stringValue = @"Le modifiche vengono applicate contemporaneamente a tutti gli schermi connessi.";
        }
    } else {
        if (_selectedDisplayUUID) {
            NSScreen *s = [self screenForUUID:_selectedDisplayUUID];
            NSDictionary *entry = [self configForScreenUUID:_selectedDisplayUUID];
            BOOL enabled = [entry[@"enabled"] boolValue];
            if (!enabled) {
                _hintLabel.stringValue = @"Angoli disattivati per questo display.";
                return;
            }
            uint32_t did = s ? [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue] : 0;
            BOOL isBuiltin = s ? CGDisplayIsBuiltin(did) : NO;
            NSInteger r = [entry[@"radius"] integerValue];
            if (isBuiltin) {
                if (r <= kDefaultRadius) {
                    _hintLabel.stringValue = @"Gli angoli superiori del display integrato sono curvati via hardware a 23 pt e vengono disegnati solo per raggi superiori.";
                } else {
                    _hintLabel.stringValue = @"Raggio superiore a 23 pt: gli angoli superiori verranno disegnati oltre la curvatura hardware.";
                }
            } else {
                _hintLabel.stringValue = @"Tutti gli angoli selezionati verranno applicati a questo display.";
            }
        }
    }
}

- (void)loginChanged:(NSButton *)b {
    SMAppService *a = SMAppService.mainAppService;
    NSError *e = nil;
    if (b.state == NSControlStateValueOn) [a registerAndReturnError:&e];
    else [a unregisterAndReturnError:&e];
    if (e) {
        b.state = (a.status == SMAppServiceStatusEnabled) ? NSControlStateValueOn : NSControlStateValueOff;
    }
}

- (void)onApplyToAllChanged:(NSButton *)sender {
    BOOL applyToAll = (sender.state == NSControlStateValueOn);
    [self setApplyToAllScreens:applyToAll];
    [self updateUI];
    [self invalidateLayoutAndRebuild];
}

- (void)onDisplayPopupChanged:(NSPopUpButton *)sender {
    NSInteger idx = sender.indexOfSelectedItem;
    if (idx >= 0 && idx < sender.numberOfItems) {
        NSMenuItem *item = [sender itemAtIndex:idx];
        NSString *uuid = item.representedObject;
        if (uuid) {
            _selectedDisplayUUID = [uuid copy];
            [self updateUI];
        }
    }
}

- (void)onDisplaySwitchChanged:(NSSwitch *)sender {
    [[NSHapticFeedbackManager defaultPerformer] performFeedbackPattern:NSHapticFeedbackPatternGeneric
                                                       performanceTime:NSHapticFeedbackPerformanceTimeDefault];
    BOOL enabled = (sender.state == NSControlStateValueOn);
    if (_selectedDisplayUUID) {
        NSMutableDictionary *entry = [self ensureConfigForScreenUUID:_selectedDisplayUUID];
        entry[@"enabled"] = @(enabled);
        NSMutableDictionary *mc = [[self multiConfig] mutableCopy] ?: [NSMutableDictionary new];
        mc[_selectedDisplayUUID] = entry;
        [self setMultiConfig:mc];
        [self updateUI];
        [self invalidateLayoutAndRebuild];
    }
}

- (void)onMockupCornersChanged:(CornerMask)newCorners {
    if (_mockup && _mockup.corners != newCorners) {
        _mockup.corners = newCorners;
    }
    BOOL applyToAll = [self applyToAllScreens];
    if (applyToAll) {
        NSMutableDictionary *gc = [[self genericConfig] mutableCopy];
        gc[@"corners"] = @(newCorners);
        [self setGenericConfig:gc];
        [self invalidateLayoutAndRebuild];
    } else {
        if (_selectedDisplayUUID) {
            NSMutableDictionary *entry = [self ensureConfigForScreenUUID:_selectedDisplayUUID];
            entry[@"corners"] = @(newCorners);
            NSMutableDictionary *mc = [[self multiConfig] mutableCopy] ?: [NSMutableDictionary new];
            mc[_selectedDisplayUUID] = entry;
            [self setMultiConfig:mc];
            [self invalidateLayoutAndRebuild];
        }
    }
}

- (void)onSliderChanged:(NSSlider *)s {
    NSInteger r = lround(s.doubleValue);
    s.accessibilityValueDescription = [NSString stringWithFormat:@"%ld pt", (long)r];
    BOOL applyToAll = [self applyToAllScreens];
    if (applyToAll) {
        NSDictionary *gc = [self genericConfig];
        if ([gc[@"radius"] integerValue] == r) return;
        NSMutableDictionary *mut = [gc mutableCopy];
        mut[@"radius"] = @(r);
        [self setGenericConfig:mut];
        if (_sliderLabel) {
            _sliderLabel.stringValue = [NSString stringWithFormat:@"Raggio: %ld pt", (long)r];
            _sliderLabel.textColor = NSColor.labelColor;
        }
        [self updateHintLabel];
        [self invalidateLayoutAndRebuild];
        [[NSHapticFeedbackManager defaultPerformer] performFeedbackPattern:NSHapticFeedbackPatternAlignment
                                                           performanceTime:NSHapticFeedbackPerformanceTimeDefault];
    } else {
        if (_selectedDisplayUUID) {
            NSMutableDictionary *entry = [self ensureConfigForScreenUUID:_selectedDisplayUUID];
            if ([entry[@"radius"] integerValue] == r) return;
            entry[@"radius"] = @(r);
            NSMutableDictionary *mc = [[self multiConfig] mutableCopy] ?: [NSMutableDictionary new];
            mc[_selectedDisplayUUID] = entry;
            [self setMultiConfig:mc];
            if (_sliderLabel) {
                BOOL enabled = [entry[@"enabled"] boolValue];
                if (enabled) {
                    _sliderLabel.stringValue = [NSString stringWithFormat:@"Raggio: %ld pt", (long)r];
                    _sliderLabel.textColor = NSColor.labelColor;
                } else {
                    _sliderLabel.stringValue = [NSString stringWithFormat:@"Raggio memorizzato: %ld pt (inattivo)", (long)r];
                    _sliderLabel.textColor = NSColor.secondaryLabelColor;
                }
            }
            [self updateHintLabel];
            [self invalidateLayoutAndRebuild];
            [[NSHapticFeedbackManager defaultPerformer] performFeedbackPattern:NSHapticFeedbackPatternAlignment
                                                               performanceTime:NSHapticFeedbackPerformanceTimeDefault];
        }
    }
}

@end

int main(void) {
    @autoreleasepool {
        NSApplication *a = NSApplication.sharedApplication;
        D *d = [D new];
        a.delegate = d;
        a.activationPolicy = NSApplicationActivationPolicyAccessory;
        [a run];
    }
    return 0;
}
