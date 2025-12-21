# Phase 4: Polish & App Store Release (2-4 weeks)

> **Goal**: Production-ready app submitted to App Store

## Prerequisites

- Phase 3 complete (Apple Pencil support)
- Apple Developer Program membership ($99/year)
- Test devices covering target iPads

## Milestones

- [ ] 4.1 App lifecycle handling
- [ ] 4.2 Performance optimization
- [ ] 4.3 Safe area & display handling
- [ ] 4.4 Settings & preferences
- [ ] 4.5 App Store assets
- [ ] 4.6 GPL compliance
- [ ] 4.7 TestFlight beta
- [ ] 4.8 App Store submission

---

## 4.1 App Lifecycle Handling

### Background/Foreground Transitions

```objc
// In OTTDAppDelegate

- (void)applicationWillResignActive:(UIApplication *)application {
    // Pause the game
    VideoDriver_iOS *driver = GetIOSVideoDriver();
    if (driver) {
        driver->PauseGame();
    }
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Autosave
    VideoDriver_iOS *driver = GetIOSVideoDriver();
    if (driver) {
        driver->AutosaveGame();
    }
    
    // Request background time for save completion
    UIBackgroundTaskIdentifier taskId = [application beginBackgroundTaskWithExpirationHandler:^{
        [application endBackgroundTask:taskId];
    }];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // Wait for save to complete
        sleep(2);
        [application endBackgroundTask:taskId];
    });
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Refresh display
    VideoDriver_iOS *driver = GetIOSVideoDriver();
    if (driver) {
        driver->RefreshDisplay();
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Optionally unpause (or leave paused for user to resume)
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    // Free caches
    VideoDriver_iOS *driver = GetIOSVideoDriver();
    if (driver) {
        driver->FreeCaches();
    }
}
```

### Save Game Integration

```cpp
void VideoDriver_iOS::AutosaveGame() {
    // Use OpenTTD's existing autosave mechanism
    DoAutoOrNetsave(-1);
}

void VideoDriver_iOS::PauseGame() {
    // Pause if in-game
    if (_game_mode == GM_NORMAL && !_pause_mode) {
        DoCommandP(0, PM_PAUSED_NORMAL, 1, CMD_PAUSE);
        _was_auto_paused = true;
    }
}
```

### Tasks

1. Implement app delegate lifecycle methods
2. Add autosave on background
3. Add pause on resign active
4. Handle memory warnings
5. Test background/foreground transitions
6. Verify save games persist correctly

---

## 4.2 Performance Optimization

### Frame Rate Management

```objc
// CADisplayLink with ProMotion support
- (void)setupDisplayLink {
    CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:self 
                                                             selector:@selector(render:)];
    
    // Prefer 60fps, allow 120fps on ProMotion displays
    if (@available(iOS 15.0, *)) {
        displayLink.preferredFrameRateRange = CAFrameRateRangeMake(30, 120, 60);
    } else {
        displayLink.preferredFramesPerSecond = 60;
    }
    
    [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.displayLink = displayLink;
}

- (void)render:(CADisplayLink *)displayLink {
    @autoreleasepool {
        self.driver->MainLoop();
    }
}
```

### Thermal Throttling

```objc
// Monitor thermal state
- (void)setupThermalMonitoring {
    [[NSNotificationCenter defaultCenter] addObserver:self
        selector:@selector(thermalStateChanged:)
        name:NSProcessInfoThermalStateDidChangeNotification
        object:nil];
}

- (void)thermalStateChanged:(NSNotification *)notification {
    NSProcessInfoThermalState state = [[NSProcessInfo processInfo] thermalState];
    
    switch (state) {
        case NSProcessInfoThermalStateNominal:
        case NSProcessInfoThermalStateFair:
            // Normal operation
            self.displayLink.preferredFramesPerSecond = 60;
            break;
            
        case NSProcessInfoThermalStateSerious:
            // Reduce frame rate
            self.displayLink.preferredFramesPerSecond = 30;
            break;
            
        case NSProcessInfoThermalStateCritical:
            // Minimal updates
            self.displayLink.preferredFramesPerSecond = 20;
            // Show warning to user
            break;
    }
}
```

### Memory Management

```cpp
void VideoDriver_iOS::FreeCaches() {
    // Clear sprite cache (OpenTTD function)
    GfxClearSpriteCache();
    
    // Clear font cache
    ClearFontCache();
    
    // Notify for additional cleanup
    InvalidateWindowData(WC_NONE, 0);
}
```

### Tasks

1. Set up CADisplayLink with proper frame rates
2. Monitor thermal state and adjust performance
3. Handle memory warnings appropriately
4. Profile on older supported iPads
5. Verify no memory leaks

---

## 4.3 Safe Area & Display Handling

### Safe Area Insets

```objc
- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    
    UIEdgeInsets insets = self.view.safeAreaInsets;
    
    // Notify OpenTTD of safe area
    self.driver->SetSafeAreaInsets(
        insets.top, insets.left, insets.bottom, insets.right);
}
```

### Integration with OpenTTD UI

```cpp
void VideoDriver_iOS::SetSafeAreaInsets(int top, int left, int bottom, int right) {
    _safe_area.top = top;
    _safe_area.left = left;
    _safe_area.bottom = bottom;
    _safe_area.right = right;
    
    // Trigger UI relayout
    RelocateAllWindows(_screen.width, _screen.height);
}
```

### Split View & Slide Over

```objc
// Handle window size changes
- (void)viewWillTransitionToSize:(CGSize)size 
      withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // Resize game during transition
        CGFloat scale = self.view.contentScaleFactor;
        self.driver->HandleResize(size.width * scale, size.height * scale);
    } completion:nil];
}
```

### Tasks

1. Read and apply safe area insets
2. Position UI elements within safe area
3. Handle Split View resizing
4. Handle Slide Over mode
5. Test on various iPad models
6. Handle rotation (landscape only)

---

## 4.4 Settings & Preferences

### iOS Settings Bundle

Create `Settings.bundle/Root.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>PreferenceSpecifiers</key>
    <array>
        <dict>
            <key>Type</key>
            <string>PSGroupSpecifier</string>
            <key>Title</key>
            <string>Graphics</string>
        </dict>
        <dict>
            <key>Type</key>
            <string>PSToggleSwitchSpecifier</string>
            <key>Title</key>
            <string>Show FPS Counter</string>
            <key>Key</key>
            <string>show_fps</string>
            <key>DefaultValue</key>
            <false/>
        </dict>
        <dict>
            <key>Type</key>
            <string>PSGroupSpecifier</string>
            <key>Title</key>
            <string>Touch Controls</string>
        </dict>
        <dict>
            <key>Type</key>
            <string>PSSliderSpecifier</string>
            <key>Key</key>
            <string>long_press_duration</string>
            <key>DefaultValue</key>
            <real>0.5</real>
            <key>MinimumValue</key>
            <real>0.3</real>
            <key>MaximumValue</key>
            <real>1.0</real>
        </dict>
    </array>
</dict>
</plist>
```

### Reading Settings

```objc
+ (void)syncSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Register defaults
    [defaults registerDefaults:@{
        @"show_fps": @NO,
        @"long_press_duration": @0.5,
        @"haptic_feedback": @YES,
    }];
    
    // Apply to game
    VideoDriver_iOS *driver = GetIOSVideoDriver();
    driver->SetShowFPS([defaults boolForKey:@"show_fps"]);
    driver->SetLongPressDuration([defaults floatForKey:@"long_press_duration"]);
}
```

### Tasks

1. Create Settings.bundle
2. Add key settings (FPS, touch sensitivity, haptics)
3. Read settings at launch
4. Apply settings changes in real-time
5. Document available settings

---

## 4.5 App Store Assets

### Required Assets

| Asset | Size | Notes |
|-------|------|-------|
| App Icon | 1024x1024 | No transparency, no rounded corners |
| Screenshots | Various | iPad Pro 12.9" (2732x2048) required |
| App Preview | Optional | 30 second video |

### Screenshot Scenes

1. **Main Menu** - Clean, shows logo
2. **Gameplay Overview** - Busy map with trains
3. **Building** - Laying track with touch
4. **Apple Pencil** - Precision placement
5. **Vehicle List** - Management screens

### App Store Description

```markdown
# OpenTTD - Transport Tycoon

Build your transport empire! OpenTTD is an open-source simulation game 
based on Transport Tycoon Deluxe.

## Features

• Build and manage rail, road, air, and water transport networks
• Play on procedurally generated or custom maps
• Full touch and gesture support
• Apple Pencil support for precision building
• Works offline - no internet required

## Touch Controls

• Tap to select and build
• Long-press for context menus
• Pinch to zoom
• Drag to pan the map
• Apple Pencil for pixel-perfect placement

## Open Source

OpenTTD is free software under the GPL license. 
Source code: https://github.com/[your-repo]

No in-app purchases. No ads. Just the game.
```

### Tasks

1. Create 1024x1024 app icon
2. Capture 6.5" and 12.9" screenshots
3. Write App Store description
4. Add keywords for discovery
5. Create privacy policy URL
6. Set age rating (likely 4+)

---

## 4.6 GPL Compliance

### Requirements for App Store

The GPL v2 requires source code availability. For App Store:

1. **Include source code link** in app description
2. **Provide source on request** (within 3 years)
3. **Include license** in app's legal section

### In-App License Display

```objc
- (void)showLicenseInfo {
    NSString *licensePath = [[NSBundle mainBundle] pathForResource:@"COPYING" ofType:@"md"];
    NSString *license = [NSString stringWithContentsOfFile:licensePath 
                                                  encoding:NSUTF8StringEncoding 
                                                     error:nil];
    
    UIAlertController *alert = [UIAlertController 
        alertControllerWithTitle:@"License"
                         message:license
                  preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
```

### App Store Metadata

In the description, include:
```
This is open-source software distributed under the GPL v2 license.
Source code is available at: https://github.com/[your-repo]
```

### Tasks

1. Include COPYING.md in app bundle
2. Add "About" screen with license info
3. Add source code URL to description
4. Verify GPL compliance with legal review

---

## 4.7 TestFlight Beta

### Pre-Release Checklist

- [ ] All features working
- [ ] No crashes in 30-minute sessions
- [ ] Save/load works correctly
- [ ] All supported iPad models tested
- [ ] Accessibility basics work
- [ ] Localization checked

### TestFlight Setup

1. Archive build in Xcode
2. Upload to App Store Connect
3. Add TestFlight testers
4. Write beta release notes
5. Submit for TestFlight review

### Beta Release Notes Template

```markdown
## OpenTTD for iPad - Beta [version]

Thanks for testing! Please report issues at: [issue tracker URL]

### What to Test
- Basic gameplay (building, vehicles, etc.)
- Touch controls (pan, zoom, long-press)
- Apple Pencil (if you have one)
- Save/load games
- App suspend/resume

### Known Issues
- [List any known bugs]

### Feedback
Please include:
- iPad model
- iPadOS version
- Steps to reproduce any bugs
- Screenshots if helpful
```

### Tasks

1. Create App Store Connect app record
2. Upload first beta build
3. Add internal testers
4. Fix critical issues from feedback
5. Expand to external testers
6. Iterate on feedback

---

## 4.8 App Store Submission

### Pre-Submission Checklist

- [ ] All TestFlight feedback addressed
- [ ] No critical or major bugs
- [ ] Performance acceptable on all targets
- [ ] All metadata complete
- [ ] Screenshots uploaded
- [ ] Privacy policy URL valid
- [ ] Contact information correct
- [ ] Pricing set (Free)

### Review Guidelines Considerations

| Guideline | Status | Notes |
|-----------|--------|-------|
| 2.1 App Completeness | ✓ | Full game, no stubs |
| 2.3 Accurate Metadata | ✓ | Screenshots match gameplay |
| 3.1.1 In-App Purchase | N/A | No IAP |
| 4.2 Minimum Functionality | ✓ | Full game experience |
| 5.1 Privacy | ✓ | No data collection |

### Submission Steps

1. Select build in App Store Connect
2. Complete all metadata fields
3. Submit for review
4. Respond to any reviewer questions
5. Approve release (manual or automatic)

### Post-Launch

1. Monitor crash reports
2. Respond to reviews
3. Plan update roadmap
4. Consider feature requests

### Tasks

1. Final QA pass
2. Complete all App Store metadata
3. Submit for review
4. Address any rejection feedback
5. Launch!

---

## Timeline Summary

| Week | Phase | Activities |
|------|-------|------------|
| 1 | 4.1-4.2 | Lifecycle, performance |
| 2 | 4.3-4.4 | Display handling, settings |
| 3 | 4.5-4.6 | Assets, GPL compliance |
| 4 | 4.7 | TestFlight beta |
| 5+ | 4.8 | Iterate, submit, launch |

---

## Success Criteria

Phase 4 is complete when:
1. App passes App Store review
2. Successfully available for download
3. No critical issues in first week
4. GPL compliance verified

---

## Post-Launch Roadmap Ideas

- iCloud save sync
- Game Center achievements
- External keyboard shortcuts
- Gamepad support
- Mac Catalyst version
- Multiplayer improvements

---

**Congratulations!** You've ported OpenTTD to iPad! 🎉
