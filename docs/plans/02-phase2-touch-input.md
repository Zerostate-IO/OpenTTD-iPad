# Phase 2: Touch Input Polish (2-3 weeks)

> **Goal**: Full gesture support, comfortable touch-only gameplay

## Prerequisites

- Phase 1 complete (game launches, basic tap works)

## Milestones

- [ ] 2.1 Gesture recognition system
- [ ] 2.2 Right-click emulation (long-press)
- [ ] 2.3 Viewport pan (drag)
- [ ] 2.4 Pinch-to-zoom
- [ ] 2.5 Virtual keyboard integration
- [ ] 2.6 UI touch target improvements
- [ ] 2.7 Floating action toolbar

---

## 2.1 Gesture Recognition System

### File: `src/video/ios/ios_touch.h`

```cpp
#ifndef VIDEO_IOS_TOUCH_H
#define VIDEO_IOS_TOUCH_H

#include <map>
#include <chrono>
#include "../../core/geometry_type.hpp"

enum class GestureState {
    IDLE,
    TAP_PENDING,          // Waiting to see if it's a tap or drag
    DRAGGING,             // Single finger drag (pan)
    LONG_PRESS_PENDING,   // Waiting for long-press threshold
    TWO_FINGER_PAN,       // Two finger drag
    PINCH_ZOOM,           // Pinch gesture active
};

struct TouchPoint {
    int touch_id;
    Point position;
    Point start_position;
    std::chrono::steady_clock::time_point start_time;
    bool is_active;
};

class TouchGestureRecognizer {
public:
    static constexpr int LONG_PRESS_THRESHOLD_MS = 500;
    static constexpr int TAP_MOVEMENT_THRESHOLD = 15;  // pixels
    static constexpr int DOUBLE_TAP_INTERVAL_MS = 300;
    
    TouchGestureRecognizer();
    
    void TouchBegan(int touch_id, float x, float y);
    void TouchMoved(int touch_id, float x, float y);
    void TouchEnded(int touch_id, float x, float y);
    void Update();  // Called each frame for time-based gestures
    
    // Output: translated mouse events
    bool HasPendingClick() const { return pending_click; }
    bool HasPendingRightClick() const { return pending_right_click; }
    Point GetClickPosition() const { return click_position; }
    
    bool IsDragging() const { return state == GestureState::DRAGGING; }
    Point GetDragDelta() const { return drag_delta; }
    
    bool IsPinching() const { return state == GestureState::PINCH_ZOOM; }
    float GetPinchScale() const { return pinch_scale; }
    Point GetPinchCenter() const { return pinch_center; }
    
private:
    GestureState state;
    std::map<int, TouchPoint> active_touches;
    
    // Output state
    bool pending_click;
    bool pending_right_click;
    Point click_position;
    Point drag_delta;
    float pinch_scale;
    Point pinch_center;
    
    // For double-tap detection
    std::chrono::steady_clock::time_point last_tap_time;
    Point last_tap_position;
    
    void TransitionState(GestureState new_state);
    float GetDistanceBetweenTouches();
    Point GetMidpointBetweenTouches();
};

#endif /* VIDEO_IOS_TOUCH_H */
```

### Implementation Notes

The gesture recognizer is a state machine:

```
IDLE
  ↓ (finger down)
TAP_PENDING ──────────────────────→ LONG_PRESS (500ms timer)
  ↓ (moved > threshold)               ↓ (finger up)
DRAGGING                           Right-click
  ↓ (finger up)
Pan complete

TAP_PENDING
  ↓ (second finger down)
TWO_FINGER_PAN or PINCH_ZOOM
```

### Tasks

1. Create `TouchGestureRecognizer` class
2. Implement state machine transitions
3. Add timing for long-press detection
4. Track multiple touch points
5. Integrate with VideoDriver_iOS

---

## 2.2 Right-Click Emulation

### Long-Press Implementation

```cpp
void TouchGestureRecognizer::Update() {
    if (state == GestureState::LONG_PRESS_PENDING) {
        auto now = std::chrono::steady_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(
            now - active_touches.begin()->second.start_time);
        
        if (duration.count() >= LONG_PRESS_THRESHOLD_MS) {
            // Trigger right-click
            pending_right_click = true;
            click_position = active_touches.begin()->second.position;
            
            // Provide haptic feedback
            TriggerHapticFeedback();
            
            TransitionState(GestureState::IDLE);
        }
    }
}
```

### Haptic Feedback

```objc
void TriggerHapticFeedback() {
    UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] 
        initWithStyle:UIImpactFeedbackStyleMedium];
    [generator impactOccurred];
}
```

### Alternative: Two-Finger Tap

```cpp
void TouchGestureRecognizer::TouchBegan(int touch_id, float x, float y) {
    // ...
    if (active_touches.size() == 2) {
        // Two fingers down simultaneously = right-click
        pending_right_click = true;
        click_position = GetMidpointBetweenTouches();
    }
}
```

### Tasks

1. Implement long-press timer in gesture recognizer
2. Add haptic feedback for long-press
3. Implement two-finger tap as alternative right-click
4. Map right-click to OpenTTD's `_right_button_down`
5. Test context menus, demolition, etc.

---

## 2.3 Viewport Pan

### Drag-to-Pan Implementation

```cpp
void TouchGestureRecognizer::TouchMoved(int touch_id, float x, float y) {
    auto it = active_touches.find(touch_id);
    if (it == active_touches.end()) return;
    
    Point new_pos = {static_cast<int>(x), static_cast<int>(y)};
    
    if (state == GestureState::TAP_PENDING) {
        // Check if movement exceeds threshold
        int dx = new_pos.x - it->second.start_position.x;
        int dy = new_pos.y - it->second.start_position.y;
        
        if (abs(dx) > TAP_MOVEMENT_THRESHOLD || abs(dy) > TAP_MOVEMENT_THRESHOLD) {
            TransitionState(GestureState::DRAGGING);
        }
    }
    
    if (state == GestureState::DRAGGING) {
        // Calculate delta for viewport scrolling
        drag_delta.x = new_pos.x - it->second.position.x;
        drag_delta.y = new_pos.y - it->second.position.y;
    }
    
    it->second.position = new_pos;
}
```

### Viewport Integration

In `VideoDriver_iOS::InputLoop()`:

```cpp
void VideoDriver_iOS::InputLoop() {
    gesture_recognizer.Update();
    
    if (gesture_recognizer.IsDragging()) {
        Point delta = gesture_recognizer.GetDragDelta();
        
        // Scroll the main viewport
        Window *w = GetMainWindow();
        if (w != nullptr) {
            ScrollMainWindowTo(
                w->viewport->scrollpos_x - delta.x,
                w->viewport->scrollpos_y - delta.y
            );
        }
    }
}
```

### Tasks

1. Detect drag gesture (movement > threshold)
2. Calculate movement delta
3. Integrate with OpenTTD viewport scrolling
4. Add momentum/inertia scrolling (optional)
5. Test smooth panning

---

## 2.4 Pinch-to-Zoom

### Pinch Detection

```cpp
void TouchGestureRecognizer::TouchMoved(int touch_id, float x, float y) {
    // ...
    
    if (active_touches.size() == 2 && state == GestureState::PINCH_ZOOM) {
        float current_distance = GetDistanceBetweenTouches();
        pinch_scale = current_distance / initial_pinch_distance;
        pinch_center = GetMidpointBetweenTouches();
    }
}

float TouchGestureRecognizer::GetDistanceBetweenTouches() {
    if (active_touches.size() != 2) return 0;
    
    auto it = active_touches.begin();
    Point p1 = it->second.position;
    ++it;
    Point p2 = it->second.position;
    
    float dx = p2.x - p1.x;
    float dy = p2.y - p1.y;
    return sqrtf(dx * dx + dy * dy);
}
```

### Zoom Integration

OpenTTD uses discrete zoom levels. Map pinch scale to zoom:

```cpp
void VideoDriver_iOS::HandlePinchZoom() {
    float scale = gesture_recognizer.GetPinchScale();
    Point center = gesture_recognizer.GetPinchCenter();
    
    static float accumulated_scale = 1.0f;
    accumulated_scale *= scale;
    
    if (accumulated_scale > 1.5f) {
        // Zoom in
        DoZoomInOutWindow(ZOOM_IN, GetMainWindow());
        accumulated_scale = 1.0f;
    } else if (accumulated_scale < 0.67f) {
        // Zoom out
        DoZoomInOutWindow(ZOOM_OUT, GetMainWindow());
        accumulated_scale = 1.0f;
    }
}
```

### Tasks

1. Detect two-finger gesture start
2. Calculate pinch scale factor
3. Map to OpenTTD zoom levels
4. Center zoom on pinch midpoint
5. Test zoom in/out

---

## 2.5 Virtual Keyboard Integration

### Show/Hide Keyboard

```objc
// In ios_wnd.mm
@interface OTTD_iOSView () <UIKeyInput>
@property (nonatomic, assign) BOOL keyboardActive;
@end

@implementation OTTD_iOSView

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)showKeyboard {
    self.keyboardActive = YES;
    [self becomeFirstResponder];
}

- (void)hideKeyboard {
    self.keyboardActive = NO;
    [self resignFirstResponder];
}

#pragma mark - UIKeyInput

- (BOOL)hasText {
    return YES;
}

- (void)insertText:(NSString *)text {
    // Convert to OpenTTD key events
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        self.driver->HandleKeyPress(c);
    }
}

- (void)deleteBackward {
    self.driver->HandleKeyPress(WKC_BACKSPACE);
}

@end
```

### Integration with OpenTTD EditBox

Override `EditBoxLostFocus()` and add `EditBoxGainedFocus()`:

```cpp
void VideoDriver_iOS::EditBoxGainedFocus() {
    [this->view showKeyboard];
}

void VideoDriver_iOS::EditBoxLostFocus() {
    [this->view hideKeyboard];
}
```

### Tasks

1. Implement UIKeyInput protocol on view
2. Handle keyboard show/hide lifecycle
3. Convert text input to OpenTTD key events
4. Handle backspace and special keys
5. Adjust viewport when keyboard appears
6. Test text input (company names, etc.)

---

## 2.6 UI Touch Target Improvements

### Approach

Increase effective touch targets without changing visual appearance:

```cpp
// In window_gui.cpp or similar
#ifdef __APPLE__
#include <TargetConditionals.h>
#if TARGET_OS_IOS
constexpr int TOUCH_TARGET_PADDING = 8;  // Extra hit area in pixels
#else
constexpr int TOUCH_TARGET_PADDING = 0;
#endif
#endif

bool IsPointInWidget(const NWidgetBase *widget, Point pt) {
    Rect bounds = widget->GetCurrentRect();
    
    // Expand bounds for touch
    bounds.left -= TOUCH_TARGET_PADDING;
    bounds.top -= TOUCH_TARGET_PADDING;
    bounds.right += TOUCH_TARGET_PADDING;
    bounds.bottom += TOUCH_TARGET_PADDING;
    
    return IsInsideBS(pt.x, bounds.left, bounds.right - bounds.left) &&
           IsInsideBS(pt.y, bounds.top, bounds.bottom - bounds.top);
}
```

### Scrollbar Touch Improvement

Make scrollbars easier to grab:

```cpp
#if TARGET_OS_IOS
// Minimum scrollbar thumb size for touch
constexpr int MIN_SCROLLBAR_THUMB_SIZE = 44;
#endif
```

### Tasks

1. Add touch target padding to widget hit testing
2. Increase minimum scrollbar thumb size
3. Test toolbar button accessibility
4. Test scrollbar usability
5. Verify no overlapping hit areas

---

## 2.7 Floating Action Toolbar

### Design

A floating toolbar providing quick access to common actions:

```
┌─────────────────────────────────────────────────────┐
│ [Train] [Road] [Settings] [Money] [Map] [||] [>>]  │
└─────────────────────────────────────────────────────┘
    F1     F2      F10       F11    F4   Pause  FF
```

### Implementation

```objc
// ios_toolbar.h
@interface OTTD_TouchToolbar : UIView

- (void)setupButtons;
- (void)setVisible:(BOOL)visible animated:(BOOL)animated;

@end

// ios_toolbar.mm
@implementation OTTD_TouchToolbar

- (void)setupButtons {
    NSArray *buttons = @[
        @{@"icon": @"train", @"key": @(WKC_F1)},
        @{@"icon": @"car", @"key": @(WKC_F2)},
        @{@"icon": @"gear", @"key": @(WKC_F10)},
        @{@"icon": @"dollarsign", @"key": @(WKC_F11)},
        @{@"icon": @"map", @"key": @(WKC_F4)},
        @{@"icon": @"pause", @"key": @(WKC_PAUSE)},
        @{@"icon": @"forward.fill", @"key": @(WKC_TAB)},
    ];
    
    for (NSDictionary *config in buttons) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        UIImage *image = [UIImage systemImageNamed:config[@"icon"]];
        [button setImage:image forState:UIControlStateNormal];
        button.tag = [config[@"key"] integerValue];
        [button addTarget:self action:@selector(buttonTapped:) 
                 forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:button];
    }
}

- (void)buttonTapped:(UIButton *)sender {
    // Send key event to OpenTTD
    VideoDriver_iOS *driver = GetIOSVideoDriver();
    driver->HandleKeyPress(static_cast<int>(sender.tag));
}

@end
```

### Positioning

- Default: Bottom of screen, centered
- Draggable to edges
- Auto-hide option
- Safe area aware

### Tasks

1. Create floating toolbar view class
2. Add SF Symbol icons for actions
3. Map button taps to OpenTTD key events
4. Implement drag-to-reposition
5. Add show/hide toggle
6. Save position preference
7. Test with different game modes

---

## Verification Checklist

- [ ] Long-press triggers right-click reliably
- [ ] Two-finger tap works as alternative right-click
- [ ] Drag pans viewport smoothly
- [ ] Pinch zoom works in both directions
- [ ] Virtual keyboard appears for text input
- [ ] Toolbar buttons are easy to tap
- [ ] Scrollbars are usable with touch
- [ ] Floating toolbar provides quick actions
- [ ] No gesture conflicts (tap vs drag detection)
- [ ] Haptic feedback feels responsive

---

## Success Criteria

Phase 2 is complete when:
1. All gestures work reliably
2. Right-click context menus accessible
3. Viewport navigation is fluid
4. Text input works seamlessly
5. UI is comfortable for touch

---

**Next**: [Phase 3 - Apple Pencil](./03-phase3-apple-pencil.md)
