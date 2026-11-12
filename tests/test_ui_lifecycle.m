#import <AppKit/AppKit.h>
#import <QuartzCore/QuartzCore.h>
#import <ServiceManagement/ServiceManagement.h>
#import <assert.h>
#import <mach/mach.h>
#import <objc/runtime.h>

@interface NSScreen (MockEmptyScreens)
+ (NSArray<NSScreen *> *)mock_emptyScreens;
@end

@implementation NSScreen (MockEmptyScreens)
+ (NSArray<NSScreen *> *)mock_emptyScreens {
    return @[];
}
@end

static size_t GetProcessRSS(void) {
    struct mach_task_basic_info info;
    mach_msg_type_number_t count = MACH_TASK_BASIC_INFO_COUNT;
    if (task_info(mach_task_self(), MACH_TASK_BASIC_INFO, (task_info_t)&info, &count) == KERN_SUCCESS) {
        return (size_t)info.resident_size;
    }
    return 0;
}

// Include the entire src/main.m implementation with main renamed
#define main app_main
#import "../src/main.m"
#undef main

static BOOL HasTextContaining(NSView *view, NSString *substr) {
    if ([view isKindOfClass:[NSTextField class]]) {
        NSString *s = [((NSTextField *)view).stringValue lowercaseString];
        if ([s containsString:[substr lowercaseString]]) return YES;
    }
    for (NSView *child in view.subviews) {
        if (HasTextContaining(child, substr)) return YES;
    }
    return NO;
}

static NSButton *FindButtonWithTitle(NSView *view, NSString *title) {
    if ([view isKindOfClass:[NSButton class]]) {
        NSString *btnTitle = ((NSButton *)view).title;
        if ([btnTitle isEqualToString:title]) {
            return (NSButton *)view;
        }
    }
    for (NSView *child in view.subviews) {
        NSButton *b = FindButtonWithTitle(child, title);
        if (b) return b;
    }
    return nil;
}

static NSSwitch *FindSwitch(NSView *view) {
    if ([view isKindOfClass:[NSSwitch class]]) {
        return (NSSwitch *)view;
    }
    for (NSView *child in view.subviews) {
        NSSwitch *s = FindSwitch(child);
        if (s) return s;
    }
    return nil;
}

static NSPopUpButton *FindPopUpButton(NSView *view) {
    if ([view isKindOfClass:[NSPopUpButton class]]) {
        return (NSPopUpButton *)view;
    }
    for (NSView *child in view.subviews) {
        NSPopUpButton *p = FindPopUpButton(child);
        if (p) return p;
    }
    return nil;
}

void test_mockup_view_interaction(void) {
    printf("[TEST] test_mockup_view_interaction... \n");
    NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, 400, 300)
                                                styleMask:NSWindowStyleMaskTitled
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];
    ScreenMockupView *mockup = [[ScreenMockupView alloc] initWithFrame:NSMakeRect(50, 50, 320, 150)];
    [win.contentView addSubview:mockup];
    assert(mockup.corners == (CornerTL | CornerTR | CornerBL | CornerBR));
    assert(mockup.isBuiltin == NO);
    assert(mockup.displayEnabled == YES);

    __block CornerMask callbackCorners = 0;
    mockup.onCornersChanged = ^(CornerMask c) {
        callbackCorners = c;
    };

    // 1. Test clicking all 4 corners in external/global mode (isBuiltin == NO)
    NSRect tlRect = [mockup tlRect];
    NSPoint tlLocal = NSMakePoint(NSMidX(tlRect), NSMidY(tlRect));
    NSEvent *tlClick = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                          location:[mockup convertPoint:tlLocal toView:nil]
                                     modifierFlags:0 timestamp:0 windowNumber:win.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1.0];
    [mockup mouseDown:tlClick];
    assert(!(mockup.corners & CornerTL));
    assert(callbackCorners == mockup.corners);

    NSRect trRect = [mockup trRect];
    NSPoint trLocal = NSMakePoint(NSMidX(trRect), NSMidY(trRect));
    NSEvent *trClick = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                          location:[mockup convertPoint:trLocal toView:nil]
                                     modifierFlags:0 timestamp:0 windowNumber:win.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1.0];
    [mockup mouseDown:trClick];
    assert(!(mockup.corners & CornerTR));

    NSRect blRect = [mockup blRect];
    NSPoint blLocal = NSMakePoint(NSMidX(blRect), NSMidY(blRect));
    NSEvent *blClick = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                          location:[mockup convertPoint:blLocal toView:nil]
                                     modifierFlags:0 timestamp:0 windowNumber:win.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1.0];
    [mockup mouseDown:blClick];
    assert(!(mockup.corners & CornerBL));

    NSRect brRect = [mockup brRect];
    NSPoint brLocal = NSMakePoint(NSMidX(brRect), NSMidY(brRect));
    NSEvent *brClick = [NSEvent mouseEventWithType:NSEventTypeLeftMouseDown
                                          location:[mockup convertPoint:brLocal toView:nil]
                                     modifierFlags:0 timestamp:0 windowNumber:win.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1.0];
    [mockup mouseDown:brClick];
    assert(!(mockup.corners & CornerBR));
    assert(mockup.corners == 0);

    // Toggle them all back ON
    [mockup mouseDown:tlClick];
    [mockup mouseDown:trClick];
    [mockup mouseDown:blClick];
    [mockup mouseDown:brClick];
    assert(mockup.corners == (CornerTL | CornerTR | CornerBL | CornerBR));

    // 2. Test built-in screen mode (isBuiltin == YES)
    // For compatible Mac panels (built-in screen), the user is now allowed
    // to freely modify all 4 corners (TL, TR, BL, BR).
    mockup.isBuiltin = YES;
    assert(mockup.corners == (CornerTL | CornerTR | CornerBL | CornerBR));

    // Clicks on TL and TR must now be processed and toggle the corner!
    [mockup mouseDown:tlClick];
    assert(!(mockup.corners & CornerTL));
    assert(callbackCorners == mockup.corners);

    [mockup mouseDown:trClick];
    assert(!(mockup.corners & CornerTR));

    // Clicks on BL and BR should work
    [mockup mouseDown:blClick];
    assert(!(mockup.corners & CornerBL));
    assert(mockup.corners == CornerBR);

    [mockup mouseDown:brClick];
    assert(!(mockup.corners & CornerBR));
    assert(mockup.corners == 0);

    // Re-enable all 4 corners
    [mockup mouseDown:tlClick];
    [mockup mouseDown:trClick];
    [mockup mouseDown:blClick];
    [mockup mouseDown:brClick];
    assert(mockup.corners == (CornerTL | CornerTR | CornerBL | CornerBR));

    // Verify setCorners: allows setting all 4 corners when isBuiltin == YES
    [mockup setCorners:(CornerTL | CornerTR | CornerBL | CornerBR)];
    assert(mockup.corners == (CornerTL | CornerTR | CornerBL | CornerBR));

    // Verify toggling isBuiltin back and forth preserves corner configuration
    mockup.isBuiltin = NO;
    assert(mockup.corners == (CornerTL | CornerTR | CornerBL | CornerBR));

    mockup.isBuiltin = YES;
    assert(mockup.corners == (CornerTL | CornerTR | CornerBL | CornerBR));

    // 3. Test disabled display mode (displayEnabled == NO)
    mockup.displayEnabled = NO;
    // When display is disabled, all clicks must be ignored
    [mockup mouseDown:blClick];
    assert(mockup.corners == (CornerTL | CornerTR | CornerBL | CornerBR));
    [mockup mouseDown:brClick];
    assert(mockup.corners == (CornerTL | CornerTR | CornerBL | CornerBR));

    mockup.displayEnabled = YES;
    mockup.isBuiltin = NO;

    // 4. Test tooltips for all corner rects
    id<NSViewToolTipOwner> tipOwner = (id<NSViewToolTipOwner>)mockup;
    assert([[tipOwner view:mockup stringForToolTip:0 point:tlLocal userData:NULL] containsString:@"TL"]);
    assert([[tipOwner view:mockup stringForToolTip:0 point:trLocal userData:NULL] containsString:@"TR"]);
    assert([[tipOwner view:mockup stringForToolTip:0 point:blLocal userData:NULL] containsString:@"BL"]);
    assert([[tipOwner view:mockup stringForToolTip:0 point:brLocal userData:NULL] containsString:@"BR"]);
    assert([tipOwner view:mockup stringForToolTip:0 point:NSMakePoint(0, 0) userData:NULL] == nil);

    // 5. Test VoiceOver accessibility integration
    assert(mockup.isAccessibilityElement == YES);
    assert([mockup.accessibilityRole isEqualToString:NSAccessibilityGroupRole]);
    assert(mockup.accessibilityLabel.length > 0);
    NSArray *axChildren = mockup.accessibilityChildren;
    assert(axChildren.count == 4);
    for (id el in axChildren) {
        assert([[el accessibilityRole] isEqualToString:NSAccessibilityButtonRole]);
        assert([[el accessibilityLabel] length] > 0);
        assert([[el accessibilityValue] isEqualToString:@"Active"]);
    }
    // Test accessibilityPerformPress toggles corner
    id firstAx = axChildren.firstObject;
    BOOL pressed = [firstAx accessibilityPerformPress];
    assert(pressed == YES);
    assert(!(mockup.corners & CornerTL));
    assert([[firstAx accessibilityValue] isEqualToString:@"Inactive"]);
    // Press again to toggle back
    pressed = [firstAx accessibilityPerformPress];
    assert(pressed == YES);
    assert((mockup.corners & CornerTL));
    assert([[firstAx accessibilityValue] isEqualToString:@"Active"]);

    mockup.displayEnabled = NO;
    assert(mockup.accessibilityChildren.count == 0);
    assert([mockup.accessibilityValue containsString:@"disabled"]);
    mockup.displayEnabled = YES;

    printf("PASSED\n");
}

void test_ui_construction_and_deallocation(void) {
    printf("[TEST] test_ui_construction_and_deallocation... ");
    D *delegate = [D new];
    [delegate buildMenu];

    // Show single preferences window
    [delegate showPrefs];
    NSWindow *prefsWin = [delegate valueForKey:@"_prefs"];
    assert(prefsWin != nil);
    [prefsWin layoutIfNeeded];
    assert([prefsWin.title isEqualToString:@"Rounded Corners"]);
    assert(prefsWin.tabbingMode == NSWindowTabbingModeDisallowed);

    // Verify unified controls exist
    NSButton *applyCheckbox = FindButtonWithTitle(prefsWin.contentView, @"Apply same settings to all displays");
    assert(applyCheckbox != nil);

    NSPopUpButton *popup = FindPopUpButton(prefsWin.contentView);
    assert(popup != nil);

    NSSwitch *sw = FindSwitch(prefsWin.contentView);
    assert(sw != nil);

    NSButton *quitBtn = FindButtonWithTitle(prefsWin.contentView, @"Quit Rounded Corners");
    assert(quitBtn != nil);

    // Verify accessibility attributes (Apple HIG)
    assert(applyCheckbox.accessibilityLabel.length > 0);
    assert(popup.accessibilityLabel.length > 0);
    assert(sw.accessibilityLabel.length > 0);
    assert(quitBtn.accessibilityLabel.length > 0);
    assert([quitBtn.accessibilityRole isEqualToString:NSAccessibilityButtonRole]);

    // Verify initialFirstResponder and Full Keyboard Access nextKeyView chain (Apple HIG)
    assert(prefsWin.initialFirstResponder == applyCheckbox);
    NSButton *loginBtn = FindButtonWithTitle(prefsWin.contentView, @"Launch at login");
    assert(loginBtn != nil);
    ScreenMockupView *mockupView = [delegate valueForKey:@"_mockup"];
    assert(mockupView != nil);
    NSSlider *sliderView = [delegate valueForKey:@"_slider"];
    assert(sliderView != nil);
    assert(loginBtn.nextKeyView == applyCheckbox);
    assert(applyCheckbox.nextKeyView == popup);
    assert(popup.nextKeyView == sw);
    assert(sw.nextKeyView == sliderView);
    assert(sliderView.nextKeyView == quitBtn);
    assert(quitBtn.nextKeyView == loginBtn);

    // Verify Apple HIG Form layout margins and alignments
    assert(prefsWin.contentView.frame.size.width == 480.0);
    assert(mockupView.frame.size.width == 432.0);
    assert([mockupView convertRect:mockupView.bounds toView:nil].origin.x == 24.0);
    assert([sliderView convertRect:sliderView.bounds toView:nil].origin.x == 24.0);
    assert([applyCheckbox convertRect:applyCheckbox.bounds toView:nil].origin.x == 24.0);

    // Verify wizard and obsolete elements are NOT present
    assert(FindButtonWithTitle(prefsWin.contentView, @"Cambia configurazione") == nil);
    assert(FindButtonWithTitle(prefsWin.contentView, @"Scegli MacBook") == nil);
    assert(FindButtonWithTitle(prefsWin.contentView, @"Scegli Schermo Generico") == nil);
    assert(FindButtonWithTitle(prefsWin.contentView, @"Scegli Multi-display") == nil);

    // Test Global mode (apply to all screens checked)
    [delegate setApplyToAllScreens:YES];
    [delegate updateUI];
    assert(popup.enabled == NO);
    assert(sw.enabled == NO);
    assert(sw.state == NSControlStateValueOn);
    assert([popup.title containsString:@"All connected displays"]);

    // Test Per-monitor mode (apply to all screens unchecked)
    [delegate setApplyToAllScreens:NO];
    [delegate updateUI];
    assert(popup.enabled == YES);
    assert(sw.enabled == YES);

    // Test toggling display switch OFF
    sw.state = NSControlStateValueOff;
    [delegate onDisplaySwitchChanged:sw];
    ScreenMockupView *mockup = [delegate valueForKey:@"_mockup"];
    NSSlider *slider = [delegate valueForKey:@"_slider"];
    NSTextField *sliderLabel = [delegate valueForKey:@"_sliderLabel"];
    assert(mockup.displayEnabled == NO);
    assert(slider.enabled == NO);
    assert([sliderLabel.stringValue containsString:@"inactive"]);

    // Test toggling display switch back ON
    sw.state = NSControlStateValueOn;
    [delegate onDisplaySwitchChanged:sw];
    assert(mockup.displayEnabled == YES);
    assert(slider.enabled == YES);
    assert([sliderLabel.stringValue containsString:@"Radius:"]);
    assert(![sliderLabel.stringValue containsString:@"inactive"]);

    // Test slider change updates label and multiConfig
    slider.doubleValue = 30.0;
    [delegate onSliderChanged:slider];
    assert([sliderLabel.stringValue isEqualToString:@"Radius: 30 pt"]);

    // Test mockup corners change updates multiConfig
    [delegate onMockupCornersChanged:(CornerBL)];
    assert(mockup.corners == CornerBL);

    // Test Cmd+W closes window
    NSEvent *cmdW = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                     location:NSZeroPoint
                                modifierFlags:NSEventModifierFlagCommand
                                    timestamp:0
                                 windowNumber:prefsWin.windowNumber
                                      context:nil
                                   characters:@"w"
                  charactersIgnoringModifiers:@"w"
                                    isARepeat:NO
                                      keyCode:13];
    BOOL handled = [prefsWin performKeyEquivalent:cmdW];
    assert(handled == YES);
    assert([delegate valueForKey:@"_prefs"] == nil);

    // Test Cmd+, (standard macOS preferences shortcut) keeps window key & ordered front
    [delegate showPrefs];
    prefsWin = [delegate valueForKey:@"_prefs"];
    assert(prefsWin != nil);
    NSEvent *cmdComma = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                         location:NSZeroPoint
                                    modifierFlags:NSEventModifierFlagCommand
                                        timestamp:0
                                     windowNumber:prefsWin.windowNumber
                                          context:nil
                                       characters:@","
                      charactersIgnoringModifiers:@","
                                        isARepeat:NO
                                          keyCode:43];
    assert([prefsWin performKeyEquivalent:cmdComma] == YES);
    assert([delegate valueForKey:@"_prefs"] != nil);

    // Test reopening and closing via Escape key
    [delegate showPrefs];
    prefsWin = [delegate valueForKey:@"_prefs"];
    assert(prefsWin != nil);
    NSEvent *escapeKey = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                          location:NSZeroPoint
                                     modifierFlags:0
                                         timestamp:0
                                      windowNumber:prefsWin.windowNumber
                                           context:nil
                                        characters:@"\e"
                       charactersIgnoringModifiers:@"\e"
                                         isARepeat:NO
                                           keyCode:53];
    assert([prefsWin performKeyEquivalent:escapeKey] == YES);
    assert([delegate valueForKey:@"_prefs"] == nil);

    // Test reopening and closing via Cmd+. (standard macOS alternate cancel shortcut)
    [delegate showPrefs];
    prefsWin = [delegate valueForKey:@"_prefs"];
    assert(prefsWin != nil);
    NSEvent *cmdPeriod = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                          location:NSZeroPoint
                                     modifierFlags:NSEventModifierFlagCommand
                                         timestamp:0
                                      windowNumber:prefsWin.windowNumber
                                           context:nil
                                        characters:@"."
                       charactersIgnoringModifiers:@"."
                                         isARepeat:NO
                                           keyCode:47];
    assert([prefsWin performKeyEquivalent:cmdPeriod] == YES);
    assert([delegate valueForKey:@"_prefs"] == nil);

    // Test closing via AppKit cancelOperation: responder method
    [delegate showPrefs];
    prefsWin = [delegate valueForKey:@"_prefs"];
    assert(prefsWin != nil);
    [prefsWin cancelOperation:nil];
    assert([delegate valueForKey:@"_prefs"] == nil);

    // Test reopening via reopen handler
    [delegate applicationShouldHandleReopen:NSApp hasVisibleWindows:NO];
    prefsWin = [delegate valueForKey:@"_prefs"];
    assert(prefsWin != nil);

    // Close and deallocate
    size_t rssWithUI = GetProcessRSS();
    NSNotification *closeNotif = [NSNotification notificationWithName:NSWindowWillCloseNotification object:prefsWin];
    [delegate windowWillClose:closeNotif];
    assert([delegate valueForKey:@"_prefs"] == nil);
    assert([delegate valueForKey:@"_displayPopup"] == nil);
    assert([delegate valueForKey:@"_displaySwitchLabel"] == nil);
    assert([delegate valueForKey:@"_displaySwitch"] == nil);
    assert([delegate valueForKey:@"_mockup"] == nil);
    assert([delegate valueForKey:@"_slider"] == nil);
    assert([delegate valueForKey:@"_hintLabel"] == nil);
    size_t rssAfterClose = GetProcessRSS();
    printf("(RSS with UI: %.1f MB, after close: %.1f MB) ",
           rssWithUI / (1024.0 * 1024.0), rssAfterClose / (1024.0 * 1024.0));

    // Close again
    closeNotif = [NSNotification notificationWithName:NSWindowWillCloseNotification object:prefsWin];
    [delegate windowWillClose:closeNotif];
    assert([delegate valueForKey:@"_prefs"] == nil);

    // Test multiple open/close cycles without leak
    for (int cycle = 0; cycle < 5; cycle++) {
        [delegate showPrefs];
        NSWindow *w = [delegate valueForKey:@"_prefs"];
        assert(w != nil);
        NSNotification *notif = [NSNotification notificationWithName:NSWindowWillCloseNotification object:w];
        [delegate windowWillClose:notif];
        assert([delegate valueForKey:@"_prefs"] == nil);
    }

    printf("PASSED\n");
}

void test_corner_panel_lifecycle(void) {
    printf("[TEST] test_corner_panel_lifecycle... ");
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kPrefGenericConfig];
    D *delegate = [D new];
    NSMutableArray<NSWindow *> *wins = [delegate valueForKey:@"_wins"];
    assert(wins != nil);
    assert(wins.count == 0);

    // 1. Global mode rebuild
    [delegate setApplyToAllScreens:YES];
    [delegate invalidateLayoutAndRebuild];
    NSUInteger globalWinCount = wins.count;
    assert(globalWinCount > 0);

    NSUInteger expectedCorners = 0;
    for (NSScreen *s in NSScreen.screens) {
        uint32_t did = [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        expectedCorners += CGDisplayIsBuiltin(did) ? 2 : 4;
    }
    assert(globalWinCount == expectedCorners);

    // 1b. Radius > 23 pt (e.g. 30 pt): compatible Mac screens draw top corners!
    NSMutableDictionary *gc = [[delegate genericConfig] mutableCopy];
    gc[@"radius"] = @(30);
    [delegate setGenericConfig:gc];
    [delegate invalidateLayoutAndRebuild];
    assert(wins.count == NSScreen.screens.count * 4);

    // 1c. Radius <= 23 pt (e.g. 23 pt, 16 pt): top corners on builtin screens are suppressed
    gc[@"radius"] = @(23);
    [delegate setGenericConfig:gc];
    [delegate invalidateLayoutAndRebuild];
    assert(wins.count == expectedCorners);

    gc[@"radius"] = @(16);
    [delegate setGenericConfig:gc];
    [delegate invalidateLayoutAndRebuild];
    assert(wins.count == expectedCorners);

    // Restore 23 pt
    gc[@"radius"] = @(23);
    [delegate setGenericConfig:gc];
    [delegate invalidateLayoutAndRebuild];

    // Stability across repeated rebuilds (no leaks)
    for (int i = 0; i < 10; i++) {
        [delegate invalidateLayoutAndRebuild];
        assert(wins.count == globalWinCount);
    }

    // 2. Per-monitor mode rebuild
    [delegate setApplyToAllScreens:NO];
    [delegate invalidateLayoutAndRebuild];
    NSUInteger multiWinCount = wins.count;
    assert(multiWinCount > 0);

    for (int i = 0; i < 10; i++) {
        [delegate invalidateLayoutAndRebuild];
        assert(wins.count == multiWinCount);
    }

    // 3. Disable all monitors in per-monitor mode: windows must be destroyed!
    NSMutableDictionary *mc = [[delegate multiConfig] mutableCopy] ?: [NSMutableDictionary new];
    for (NSScreen *s in NSScreen.screens) {
        uint32_t did = [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        NSString *uuid = DisplayUUID(did);
        NSMutableDictionary *entry = [mc[uuid] mutableCopy] ?: [NSMutableDictionary new];
        entry[@"enabled"] = @NO;
        mc[uuid] = entry;
    }
    [delegate setMultiConfig:mc];
    [delegate invalidateLayoutAndRebuild];
    assert(wins.count == 0);

    // 4. Re-enable monitors: windows must be restored!
    for (NSScreen *s in NSScreen.screens) {
        uint32_t did = [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        NSString *uuid = DisplayUUID(did);
        NSMutableDictionary *entry = [mc[uuid] mutableCopy];
        entry[@"enabled"] = @YES;
        mc[uuid] = entry;
    }
    [delegate setMultiConfig:mc];
    [delegate invalidateLayoutAndRebuild];
    assert(wins.count == multiWinCount);

    // 5. Per-monitor mode threshold verification for builtin display
    for (NSScreen *s in NSScreen.screens) {
        uint32_t did = [s.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
        if (CGDisplayIsBuiltin(did)) {
            NSString *uuid = DisplayUUID(did);
            NSMutableDictionary *entry = [mc[uuid] mutableCopy];

            // Case A: radius 23 pt, all 4 corners configured -> only 2 windows created (BL and BR)
            entry[@"radius"] = @(23);
            entry[@"corners"] = @(CornerTL | CornerTR | CornerBL | CornerBR);
            mc[uuid] = entry;
            [delegate setMultiConfig:mc];
            [delegate invalidateLayoutAndRebuild];

            NSUInteger builtinWins = 0;
            for (NSWindow *w in wins) {
                if (NSPointInRect(w.frame.origin, s.frame)) builtinWins++;
            }
            assert(builtinWins == 2);

            // Case B: radius 24 pt (> 23), all 4 corners configured -> 4 windows created
            entry[@"radius"] = @(24);
            mc[uuid] = entry;
            [delegate setMultiConfig:mc];
            [delegate invalidateLayoutAndRebuild];
            builtinWins = 0;
            for (NSWindow *w in wins) {
                if (NSPointInRect(w.frame.origin, s.frame)) builtinWins++;
            }
            assert(builtinWins == 4);

            // Case C: radius 23 pt, only top corners (TL | TR) configured -> 0 windows created
            entry[@"radius"] = @(23);
            entry[@"corners"] = @(CornerTL | CornerTR);
            mc[uuid] = entry;
            [delegate setMultiConfig:mc];
            [delegate invalidateLayoutAndRebuild];
            builtinWins = 0;
            for (NSWindow *w in wins) {
                if (NSPointInRect(w.frame.origin, s.frame)) builtinWins++;
            }
            assert(builtinWins == 0);

            // Case D: radius 24 pt, only top corners (TL | TR) configured -> 2 windows created (TL and TR)
            entry[@"radius"] = @(24);
            entry[@"corners"] = @(CornerTL | CornerTR);
            mc[uuid] = entry;
            [delegate setMultiConfig:mc];
            [delegate invalidateLayoutAndRebuild];
            builtinWins = 0;
            for (NSWindow *w in wins) {
                if (NSPointInRect(w.frame.origin, s.frame)) builtinWins++;
            }
            assert(builtinWins == 2);

            // Restore
            entry[@"radius"] = @(23);
            entry[@"corners"] = @(CornerTL | CornerTR | CornerBL | CornerBR);
            mc[uuid] = entry;
            [delegate setMultiConfig:mc];
            [delegate invalidateLayoutAndRebuild];
            break;
        }
    }

    printf("PASSED\n");
}

void test_settings_readability_and_radius_23(void) {
    printf("[TEST] test_settings_readability_and_radius_23... ");
    D *delegate = [D new];

    // 1. Fixed default radius is 23 pt
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kPrefGenericConfig];
    [NSUserDefaults.standardUserDefaults removeObjectForKey:kPrefLegacyRadius];
    NSDictionary *gc = [delegate genericConfig];
    assert([gc[@"radius"] integerValue] == 23);
    assert(ClampRadius(3) == kMinRadius);
    assert(ClampRadius(99) == kMaxRadius);
    assert(ClampRadius(30) == 30);

    // 2. Settings UI must NOT contain dynamic recommendation labels ("consigliato")
    [delegate showPrefs];
    NSWindow *prefsWin = [delegate valueForKey:@"_prefs"];
    assert(prefsWin != nil);
    assert(HasTextContaining(prefsWin.contentView, @"consigliato") == NO);

    // A stored radius below the minimum shows the value that is actually drawn
    NSMutableDictionary *low = [[delegate genericConfig] mutableCopy];
    low[@"radius"] = @(3);
    [delegate setGenericConfig:low];
    [delegate setApplyToAllScreens:YES];
    [delegate updateUI];
    assert(((NSSlider *)[delegate valueForKey:@"_slider"]).integerValue == kMinRadius);

    // 3. Verify footer quit button title, version label and hint label
    NSButton *quitBtn = FindButtonWithTitle(prefsWin.contentView, @"Quit Rounded Corners");
    assert(quitBtn != nil);
    assert(HasTextContaining(prefsWin.contentView, @"v1.0") == YES);
    assert(HasTextContaining(prefsWin.contentView, @"v2.0") == NO);

    NSTextField *hintLabel = [delegate valueForKey:@"_hintLabel"];
    assert(hintLabel != nil);
    [delegate setApplyToAllScreens:YES];
    [delegate updateUI];
    if (HasBuiltinScreen()) {
        assert([hintLabel.stringValue containsString:@"23 pt"]);
        NSSlider *slider = [delegate valueForKey:@"_slider"];
        slider.doubleValue = 30.0;
        [delegate onSliderChanged:slider];
        assert([hintLabel.stringValue containsString:@"greater than 23 pt"]);
        // Restore 23
        slider.doubleValue = 23.0;
        [delegate onSliderChanged:slider];
        assert([hintLabel.stringValue containsString:@"23 pt"]);
    }

    // 4. Verify migration of stale 24 -> 23 in both genericConfig and multiConfig
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;
    [ud removeObjectForKey:@"v2_radius_23_migrated"];
    [ud setObject:@{
        @"targetMode": @"all",
        @"selectedUUID": @"",
        @"radius": @(24),
        @"corners": @(15)
    } forKey:kPrefGenericConfig];
    [ud setObject:@{
        @"TEST-UUID-1": @{ @"radius": @(24), @"corners": @(15), @"enabled": @YES },
        @"TEST-UUID-2": @{ @"radius": @(30), @"corners": @(3), @"enabled": @YES }
    } forKey:kPrefMultiConfig];

    [delegate migrateLegacyConfigIfNeeded];
    NSDictionary *migratedGC = [ud dictionaryForKey:kPrefGenericConfig];
    assert([migratedGC[@"radius"] integerValue] == 23);
    NSDictionary *migratedMC = [ud dictionaryForKey:kPrefMultiConfig];
    assert([migratedMC[@"TEST-UUID-1"][@"radius"] integerValue] == 23);
    assert([migratedMC[@"TEST-UUID-2"][@"radius"] integerValue] == 30);

    // Clean up
    NSNotification *closeNotif = [NSNotification notificationWithName:NSWindowWillCloseNotification object:prefsWin];
    [delegate windowWillClose:closeNotif];

    printf("PASSED\n");
}

void test_edge_cases_and_multi_monitor_popup(void) {
    printf("[TEST] test_edge_cases_and_multi_monitor_popup... ");
    NSUserDefaults *ud = NSUserDefaults.standardUserDefaults;

    // 1. Test legacy "macbook" mode migration
    [ud removeObjectForKey:kPrefApplyToAll];
    [ud setObject:@"macbook" forKey:kPrefConfigMode];
    D *delegate = [D new];
    assert([delegate applyToAllScreens] == NO);

    [ud setObject:@"multi" forKey:kPrefConfigMode];
    assert([delegate applyToAllScreens] == NO);

    [ud setObject:@"generic" forKey:kPrefConfigMode];
    assert([delegate applyToAllScreens] == YES);

    // 2. Test genericConfig preservation when partial
    [ud setObject:@{ @"radius": @35 } forKey:kPrefGenericConfig];
    NSDictionary *gc = [delegate genericConfig];
    assert([gc[@"radius"] integerValue] == 35);
    assert([gc[@"corners"] integerValue] == (CornerTL | CornerTR | CornerBL | CornerBR));

    // 3. Test ensureConfigForScreenUUID creates complete dictionary
    NSScreen *realScreen = NSScreen.mainScreen;
    uint32_t realDid = [realScreen.deviceDescription[@"NSScreenNumber"] unsignedIntValue];
    NSString *testUUID = DisplayUUID(realDid);
    NSMutableDictionary *mc = [[delegate multiConfig] mutableCopy] ?: [NSMutableDictionary new];
    [mc removeObjectForKey:testUUID];
    [delegate setMultiConfig:mc];

    NSMutableDictionary *entry = [delegate ensureConfigForScreenUUID:testUUID];
    assert(entry[@"enabled"] != nil && [entry[@"enabled"] boolValue] == YES);
    assert(entry[@"radius"] != nil && [entry[@"radius"] integerValue] == 35); // inherited from genericConfig
    assert(entry[@"corners"] != nil);

    // 4. Test toggling display switch OFF creates complete entry and disables slider label
    [delegate showPrefs];
    [delegate setApplyToAllScreens:NO];
    [delegate setValue:testUUID forKey:@"_selectedDisplayUUID"];
    [delegate updateUI];
    NSSwitch *sw = [delegate valueForKey:@"_displaySwitch"];
    sw.state = NSControlStateValueOff;
    [delegate onDisplaySwitchChanged:sw];

    NSDictionary *savedEntry = [delegate multiConfig][testUUID];
    assert([savedEntry[@"enabled"] boolValue] == NO);
    assert([savedEntry[@"radius"] integerValue] == 35);
    assert(savedEntry[@"corners"] != nil);

    NSTextField *sliderLabel = [delegate valueForKey:@"_sliderLabel"];
    assert([sliderLabel.stringValue containsString:@"(inactive)"]);

    // Test slider change while disabled preserves enabled=NO and updates label with (inactive)
    NSSlider *slider = [delegate valueForKey:@"_slider"];
    slider.doubleValue = 40.0;
    [delegate onSliderChanged:slider];
    savedEntry = [delegate multiConfig][testUUID];
    assert([savedEntry[@"enabled"] boolValue] == NO);
    assert([savedEntry[@"radius"] integerValue] == 40);
    assert([sliderLabel.stringValue containsString:@"40 pt (inactive)"]);

    // Test mockup corners change preserves enabled=NO and radius=40
    [delegate onMockupCornersChanged:(CornerBL | CornerBR)];
    savedEntry = [delegate multiConfig][testUUID];
    assert([savedEntry[@"enabled"] boolValue] == NO);
    assert([savedEntry[@"radius"] integerValue] == 40);
    assert([savedEntry[@"corners"] integerValue] == (CornerBL | CornerBR));

    // Restore enabled=YES for real screen
    sw.state = NSControlStateValueOn;
    [delegate onDisplaySwitchChanged:sw];

    // 5. Test NSPopUpButton duplicate titles and menu item addition resilience
    NSPopUpButton *testPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    NSMenuItem *ext1 = [[NSMenuItem alloc] initWithTitle:@"🖥️ Dell U2720Q (External 1)" action:NULL keyEquivalent:@""];
    ext1.representedObject = @"DELL-UUID-1";
    [testPopup.menu addItem:ext1];

    NSMenuItem *ext2 = [[NSMenuItem alloc] initWithTitle:@"🖥️ Dell U2720Q (External 2)" action:NULL keyEquivalent:@""];
    ext2.representedObject = @"DELL-UUID-2";
    [testPopup.menu addItem:ext2];

    assert(testPopup.numberOfItems == 2);
    [testPopup selectItemAtIndex:1];
    assert(testPopup.indexOfSelectedItem == 1);
    assert([[testPopup itemAtIndex:1].representedObject isEqualToString:@"DELL-UUID-2"]);

    [testPopup selectItemAtIndex:0];
    assert(testPopup.indexOfSelectedItem == 0);
    assert([[testPopup itemAtIndex:0].representedObject isEqualToString:@"DELL-UUID-1"]);

    // Test real popup in delegate
    NSPopUpButton *popup = [delegate valueForKey:@"_displayPopup"];
    assert(popup != nil);
    [delegate updateUI];
    assert(popup.numberOfItems == (NSInteger)NSScreen.screens.count);
    assert(popup.selectedItem != nil);
    assert([[delegate valueForKey:@"_selectedDisplayUUID"] isEqualToString:popup.selectedItem.representedObject]);

    // 6. Test headless / zero-screens handling via swizzling
    Method origScreens = class_getClassMethod([NSScreen class], @selector(screens));
    Method mockScreens = class_getClassMethod([NSScreen class], @selector(mock_emptyScreens));
    method_exchangeImplementations(origScreens, mockScreens);

    [delegate updateUI];
    assert(popup.numberOfItems == 1);
    assert([[popup itemAtIndex:0].title isEqualToString:@"No displays"]);
    assert(popup.enabled == NO);
    assert(sw.enabled == NO);
    assert(sw.state == NSControlStateValueOff);
    ScreenMockupView *mockupView = [delegate valueForKey:@"_mockup"];
    assert(mockupView.displayEnabled == NO);
    assert(slider.enabled == NO);
    assert([sliderLabel.stringValue isEqualToString:@"No displays detected"]);

    // Restore real screens
    method_exchangeImplementations(origScreens, mockScreens);
    [delegate updateUI];

    // 7. Test rebuild layout cache accounts for screen frame changes in per-monitor mode
    [delegate setApplyToAllScreens:NO];
    [delegate rebuild];
    NSString *layout1 = [delegate valueForKey:@"_layout"];
    assert(layout1 != nil);

    // Verify layout string contains geometry (e.g. frame format)
    assert([layout1 containsString:@"mode:multi"]);
    assert([layout1 containsString:@"{"]); // NSStringFromRect contains '{'

    // Clean up
    NSWindow *prefsWin = [delegate valueForKey:@"_prefs"];
    if (prefsWin) {
        NSNotification *cNotif = [NSNotification notificationWithName:NSWindowWillCloseNotification object:prefsWin];
        [delegate windowWillClose:cNotif];
    }
    printf("PASSED\n");
}

int main(void) {
    @autoreleasepool {
        NSApplication *a = [NSApplication sharedApplication];
        a.activationPolicy = NSApplicationActivationPolicyAccessory;
        printf("--- Running UI & Lifecycle Test Suite ---\n");
        test_mockup_view_interaction();
        test_ui_construction_and_deallocation();
        test_corner_panel_lifecycle();
        test_settings_readability_and_radius_23();
        test_edge_cases_and_multi_monitor_popup();
        printf("--- ALL UI TESTS PASSED ---\n");
    }
    return 0;
}
