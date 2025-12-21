# Phase 3: Apple Pencil Integration (2-3 weeks)

> **Goal**: Precision input with hover preview and pencil-specific features

## Prerequisites

- Phase 2 complete (full gesture support)
- iPad with Apple Pencil support for testing

## Milestones

- [ ] 3.1 Pencil vs finger detection
- [ ] 3.2 Hover support (Pencil Pro)
- [ ] 3.3 Precision cursor mode
- [ ] 3.4 Double-tap action binding
- [ ] 3.5 Pressure sensitivity (optional)

---

## 3.1 Pencil vs Finger Detection

### Touch Type Detection

```objc
// In ios_touch.mm

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        BOOL isPencil = (touch.type == UITouchTypePencil);
        
        CGPoint location = [touch locationInView:self];
        CGFloat scale = self.contentScaleFactor;
        
        if (isPencil) {
            // Pencil input: immediate, precise
            [self handlePencilTouchBegan:touch at:location scale:scale];
        } else {
            // Finger input: use gesture recognition
            self.driver->GetGestureRecognizer().TouchBegan(
                (int)touch.hash,
                location.x * scale,
                location.y * scale
            );
        }
    }
}

- (void)handlePencilTouchBegan:(UITouch *)touch at:(CGPoint)location scale:(CGFloat)scale {
    // No gesture delay for pencil - immediate response
    int x = static_cast<int>(location.x * scale);
    int y = static_cast<int>(location.y * scale);
    
    // Store pencil state
    self.pencilState.isActive = YES;
    self.pencilState.position = {x, y};
    self.pencilState.pressure = touch.force / touch.maximumPossibleForce;
    self.pencilState.altitude = touch.altitudeAngle;
    
    // Immediate left-click
    self.driver->HandlePencilDown(x, y);
}
```

### Pencil State Structure

```cpp
// In ios_pencil.h

struct PencilState {
    bool isActive;
    Point position;
    float pressure;           // 0.0 - 1.0
    float altitude;           // 0 = parallel, π/2 = perpendicular
    float azimuth;            // Rotation around perpendicular axis
    bool isHovering;          // Pencil Pro only
};
```

### Different Behavior for Pencil

| Feature | Finger | Pencil |
|---------|--------|--------|
| Tap delay | 100ms (gesture detection) | 0ms (immediate) |
| Drag threshold | 15px | 3px |
| Right-click | Long-press 500ms | Not needed (hover) |
| Precision | Touch target padding | Exact pixel |

### Tasks

1. Detect `UITouchTypePencil` in touch handlers
2. Create `PencilState` structure
3. Bypass gesture delay for pencil input
4. Lower drag threshold for pencil
5. Test pencil vs finger response times

---

## 3.2 Hover Support (Pencil Pro)

### Hover Gesture Recognizer

Available on iPadOS 16.0+ with Pencil Pro:

```objc
// In ios_wnd.mm

- (void)setupHoverGesture {
    if (@available(iOS 16.0, *)) {
        UIHoverGestureRecognizer *hover = [[UIHoverGestureRecognizer alloc]
            initWithTarget:self action:@selector(handleHover:)];
        [self addGestureRecognizer:hover];
    }
}

- (void)handleHover:(UIHoverGestureRecognizer *)gesture API_AVAILABLE(ios(16.0)) {
    CGPoint location = [gesture locationInView:self];
    CGFloat scale = self.contentScaleFactor;
    
    int x = static_cast<int>(location.x * scale);
    int y = static_cast<int>(location.y * scale);
    
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan:
        case UIGestureRecognizerStateChanged:
            self.pencilState.isHovering = YES;
            self.pencilState.position = {x, y};
            self.driver->HandlePencilHover(x, y);
            break;
            
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
            self.pencilState.isHovering = NO;
            self.driver->HandlePencilHoverEnd();
            break;
            
        default:
            break;
    }
}
```

### Hover Integration with OpenTTD

Update cursor position during hover (shows tooltips, highlights):

```cpp
void VideoDriver_iOS::HandlePencilHover(int x, int y) {
    // Update cursor position without clicking
    _cursor.pos.x = x;
    _cursor.pos.y = y;
    
    // Mark screen as needing update for hover effects
    this->MakeDirty(0, 0, _screen.width, _screen.height);
}
```

### Hover Tooltips

OpenTTD already shows tooltips on hover. With Pencil hover:
- Tile info appears before touching
- Vehicle tooltips visible
- Button tooltips work like desktop

### Tasks

1. Add `UIHoverGestureRecognizer` (iOS 16+)
2. Handle hover state changes
3. Update cursor position on hover
4. Verify tooltips appear during hover
5. Test on Pencil Pro

---

## 3.3 Precision Cursor Mode

### Visual Cursor for Pencil

When pencil is active/hovering, show a visible cursor:

```cpp
void VideoDriver_iOS::DrawPencilCursor() {
    if (!pencil_state.isActive && !pencil_state.isHovering) return;
    
    // Draw crosshair cursor at pencil position
    Point pos = pencil_state.position;
    
    // Vertical line
    GfxDrawLine(pos.x, pos.y - 10, pos.x, pos.y + 10, PC_WHITE);
    // Horizontal line
    GfxDrawLine(pos.x - 10, pos.y, pos.x + 10, pos.y, PC_WHITE);
    // Center dot
    GfxFillRect(pos.x - 1, pos.y - 1, pos.x + 1, pos.y + 1, PC_WHITE);
}
```

### Precision Selection

Disable touch target padding when pencil is active:

```cpp
int GetTouchTargetPadding() {
#if TARGET_OS_IOS
    if (GetIOSVideoDriver()->IsPencilActive()) {
        return 0;  // No padding for pencil
    }
    return 8;  // Normal padding for finger
#else
    return 0;
#endif
}
```

### Tasks

1. Add visual cursor for pencil mode
2. Disable touch target expansion for pencil
3. Enable single-pixel selection accuracy
4. Test precise rail/road placement
5. Test small button selection

---

## 3.4 Double-Tap Action Binding

### UIPencilInteraction

Apple Pencil 2nd gen+ supports double-tap gesture:

```objc
// In ios_pencil.mm

@interface OTTD_iOSView () <UIPencilInteractionDelegate>
@end

@implementation OTTD_iOSView (Pencil)

- (void)setupPencilInteraction {
    UIPencilInteraction *interaction = [[UIPencilInteraction alloc] init];
    interaction.delegate = self;
    [self addInteraction:interaction];
}

#pragma mark - UIPencilInteractionDelegate

- (void)pencilInteractionDidTap:(UIPencilInteraction *)interaction {
    // Check user's system preference
    UIPencilPreferredAction preferredAction = UIPencilInteraction.preferredTapAction;
    
    switch (preferredAction) {
        case UIPencilPreferredActionSwitchEraser:
            // Toggle demolition tool
            [self toggleDemolitionTool];
            break;
            
        case UIPencilPreferredActionSwitchPrevious:
            // Switch to previous tool
            [self switchToPreviousTool];
            break;
            
        case UIPencilPreferredActionShowColorPalette:
            // Open tool palette
            [self openToolPalette];
            break;
            
        case UIPencilPreferredActionIgnore:
        default:
            break;
    }
}

- (void)toggleDemolitionTool {
    // Send 'R' key to toggle demolition
    self.driver->HandleKeyPress('R');
}

- (void)switchToPreviousTool {
    // Could track last-used tool and switch back
    // For now, just toggle between build and pointer
}

- (void)openToolPalette {
    // Open the construction toolbar
    self.driver->HandleKeyPress(WKC_F8);  // Landscaping toolbar
}

@end
```

### Haptic Feedback

Provide tactile confirmation:

```objc
- (void)pencilInteractionDidTap:(UIPencilInteraction *)interaction {
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc]
        initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
    
    // ... rest of handling
}
```

### Tasks

1. Add `UIPencilInteraction` to view
2. Implement `UIPencilInteractionDelegate`
3. Respect user's system preference
4. Map to sensible OpenTTD actions
5. Add haptic feedback
6. Test on Apple Pencil 2nd gen+

---

## 3.5 Pressure Sensitivity (Optional)

### Use Cases in OpenTTD

Pressure sensitivity has limited use in a strategy game, but could be used for:
- **Drawing speed**: Light pressure = slow track laying
- **Zoom control**: Pressure affects zoom speed
- **Future**: Terrain sculpting intensity

### Basic Pressure Reading

```objc
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    for (UITouch *touch in touches) {
        if (touch.type == UITouchTypePencil) {
            float pressure = touch.force / touch.maximumPossibleForce;
            self.pencilState.pressure = pressure;
            
            // Optional: use pressure for something
            // e.g., scroll speed = pressure * maxSpeed
        }
    }
}
```

### Tilt Detection

```objc
float altitude = touch.altitudeAngle;  // 0 to π/2
float azimuth = [touch azimuthAngleInView:self];  // 0 to 2π

// Could use for:
// - Angled line drawing
// - Camera rotation (future 3D mode?)
```

### Tasks

1. Read pressure values from touch
2. Read altitude/azimuth angles
3. (Optional) Map to meaningful actions
4. Document for future use

---

## Pencil Pro Features (iPadOS 17.5+)

### Barrel Roll Detection

```objc
if (@available(iOS 17.5, *)) {
    UITouch *touch = /* pencil touch */;
    CGFloat rollAngle = touch.rollAngle;
    
    // Could use for:
    // - Tool rotation
    // - Brush angle (if drawing features added)
}
```

### Squeeze Gesture

Available on Apple Pencil Pro:

```objc
// Check if Pencil Pro is connected
if (UIPencilInteraction.preferredSqueezeAction != UIPencilPreferredActionIgnore) {
    // Handle squeeze gesture via UIPencilInteractionDelegate
}
```

### Tasks

1. Detect Pencil Pro availability
2. Handle barrel roll (if useful)
3. Handle squeeze gesture (if useful)
4. Graceful degradation for older Pencils

---

## Testing Matrix

| Feature | Pencil 1st Gen | Pencil 2nd Gen | Pencil Pro |
|---------|---------------|----------------|------------|
| Basic tap | ✓ | ✓ | ✓ |
| Pressure | ✓ | ✓ | ✓ |
| Tilt | ✓ | ✓ | ✓ |
| Double-tap | ✗ | ✓ | ✓ |
| Hover | ✗ | ✗ | ✓ |
| Squeeze | ✗ | ✗ | ✓ |
| Barrel roll | ✗ | ✗ | ✓ |

---

## Verification Checklist

- [ ] Pencil vs finger correctly distinguished
- [ ] Pencil input has no gesture delay
- [ ] Hover updates cursor position
- [ ] Tooltips appear during hover
- [ ] Visual cursor shown for pencil
- [ ] Precise tile selection works
- [ ] Double-tap triggers action
- [ ] Haptic feedback on double-tap
- [ ] Works with all Pencil generations
- [ ] Graceful fallback for features

---

## Success Criteria

Phase 3 is complete when:
1. Pencil provides noticeable precision advantage
2. Hover preview works on supported devices
3. Double-tap enhances workflow
4. No regression in finger input

---

**Next**: [Phase 4 - Polish & Release](./04-phase4-release.md)
