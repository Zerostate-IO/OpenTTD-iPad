# Apple Pencil Radial Menu Design
**For OpenTTD iPad Port - Optimized for Apple Pencil Pro**

## Executive Summary
A multi-level radial menu system optimized for Apple Pencil Pro's squeeze gesture, providing quick access to 50+ building tools through an intuitive hover-based interface. The system gracefully adapts to all Apple Pencil generations.

---

## Apple Pencil Generation Support

### Apple Pencil Models Comparison

| Feature | 1st Gen | 2nd Gen | USB-C | **Pro** |
|---------|---------|---------|-------|---------|
| **Released** | 2015 | 2018 | 2023 | 2024 |
| **Pressure Sensitivity** | ✓ | ✓ | ✗ | ✓ |
| **Tilt Sensitivity** | ✓ | ✓ | ✓ | ✓ |
| **Double-Tap** | ✗ | ✓ | ✗ | ✓ |
| **Hover** | ✗ | ✓ (M2+ iPads) | ✓ (M2+ iPads) | ✓ |
| **Squeeze Gesture** | ✗ | ✗ | ✗ | **✓** |
| **Barrel Roll** | ✗ | ✗ | ✗ | **✓** |
| **Haptic Feedback** | ✗ | ✗ | ✗ | **✓** |
| **Find My Support** | ✗ | ✗ | ✗ | **✓** |
| **iPadOS Version** | 9.1+ | 12.1+ | 17.0+ | **17.5+** |

### Detection & Adaptation Strategy

#### Automatic Pencil Detection
```objc
// In ios_pencil.mm

typedef NS_ENUM(NSInteger, ApplePencilGeneration) {
    ApplePencilGen_Unknown = 0,
    ApplePencilGen_First,
    ApplePencilGen_Second,
    ApplePencilGen_USBC,
    ApplePencilGen_Pro
};

@interface PencilDetector : NSObject
+ (ApplePencilGeneration)detectConnectedPencil;
+ (BOOL)supportsDoubleclick.tap;
+ (BOOL)supportsHover;
+ (BOOL)supportsSqueeze;
+ (BOOL)supportsBarrelRoll;
@end

@implementation PencilDetector

+ (ApplePencilGeneration)detectConnectedPencil {
    if (@available(iOS 17.5, *)) {
        // Check for squeeze support (Pro only)
        if ([UIPencilInteraction preferredSqueezeAction] != UIPencilPreferredActionIgnore) {
            return ApplePencilGen_Pro;
        }
    }
    
    if (@available(iOS 12.1, *)) {
        // Check for double-tap support (2nd Gen or Pro)
        if ([UIPencilInteraction preferredTapAction] != UIPencilPreferredActionIgnore) {
            // Could be 2nd Gen or Pro, but squeeze check above would have caught Pro
            return ApplePencilGen_Second;
        }
    }
    
    // Check for USB-C vs 1st Gen (both lack double-tap)
    // No direct API to distinguish, use heuristics or manual config
    return ApplePencilGen_First; // Default to most conservative
}

+ (BOOL)supportsSqueeze {
    if (@available(iOS 17.5, *)) {
        return [UIPencilInteraction preferredSqueezeAction] != UIPencilPreferredActionIgnore;
    }
    return NO;
}

+ (BOOL)supportsDoubleTap {
    if (@available(iOS 12.1, *)) {
        return [UIPencilInteraction preferredTapAction] != UIPencilPreferredActionIgnore;
    }
    return NO;
}

+ (BOOL)supportsHover {
    // Hover requires M2+ iPad, but we can check at runtime
    if (@available(iOS 16.1, *)) {
        // Check if UIHoverGestureRecognizer is functional
        return YES; // Simplified - would need device check in reality
    }
    return NO;
}

@end
```

### User Configuration Dialog

For cases where automatic detection is ambiguous (e.g., 1st Gen vs USB-C):

```
┌─────────────────────────────────────────────┐
│  Apple Pencil Configuration                 │
├─────────────────────────────────────────────┤
│                                             │
│  Which Apple Pencil do you have?           │
│                                             │
│  ○  Apple Pencil (1st Generation)          │
│      • Round body with cap                 │
│      • Lightning connector                 │
│                                             │
│  ○  Apple Pencil (2nd Generation)          │
│      • Flat side, no cap                   │
│      • Magnetic attachment                 │
│      • Double-tap support                  │
│                                             │
│  ○  Apple Pencil (USB-C)                   │
│      • Flat side with sliding USB-C cap    │
│      • No pressure sensitivity             │
│                                             │
│  ●  Apple Pencil Pro (Detected)            │
│      • Squeeze gesture support             │
│      • Barrel roll, haptic feedback        │
│                                             │
│  [ Automatically detect in future ]        │
│                                             │
│          [Cancel]  [Confirm]               │
└─────────────────────────────────────────────┘
```

---

## Primary Activation Method: Squeeze Gesture (Apple Pencil Pro)

### Squeeze Gesture Implementation

#### UIPencilInteraction Setup
```objc
// In ios_wnd.mm

@interface OTTD_iOSView () <UIPencilInteractionDelegate>
@property (nonatomic, strong) UIPencilInteraction *pencilInteraction;
@property (nonatomic, assign) BOOL radialMenuActive;
@end

@implementation OTTD_iOSView

- (void)setupPencilInteraction API_AVAILABLE(ios(12.1)) {
    self.pencilInteraction = [[UIPencilInteraction alloc] init];
    self.pencilInteraction.delegate = self;
    [self addInteraction:self.pencilInteraction];
}

#pragma mark - UIPencilInteractionDelegate

- (void)pencilInteractionDidTap:(UIPencilInteraction *)interaction 
    API_AVAILABLE(ios(12.1)) {
    
    // Handle double-tap for 2nd Gen (fallback activation)
    if (_settings_client.gui.use_radial_menu) {
        [self showRadialMenuAtHoverPosition];
    }
}

- (BOOL)pencilInteraction:(UIPencilInteraction *)interaction 
        didReceiveSqueeze:(UIPencilInteraction.Squeeze *)squeeze 
    API_AVAILABLE(ios(17.5)) {
    
    // PRIMARY ACTIVATION METHOD for Apple Pencil Pro
    
    switch (squeeze.phase) {
        case UIPencilInteractionPhaseEnded: {
            if (!_settings_client.gui.use_radial_menu) {
                return NO; // Let system handle it
            }
            
            // Get hover pose (position where squeeze occurred)
            UIPencilHoverPose *pose = squeeze.hoverPose;
            CGPoint location = [pose locationInView:self];
            
            // Trigger haptic feedback
            UIImpactFeedbackGenerator *feedback = 
                [[UIImpactFeedbackGenerator alloc] 
                    initWithStyle:UIImpactFeedbackStyleLight];
            [feedback prepare];
            [feedback impactOccurred];
            
            // Show radial menu at squeeze location
            [self showRadialMenuAtLocation:location withPose:pose];
            
            return YES; // We handled it
        }
        
        default:
            return NO;
    }
}

- (void)showRadialMenuAtLocation:(CGPoint)location 
                        withPose:(UIPencilHoverPose *)pose 
    API_AVAILABLE(ios(17.5)) {
    
    CGFloat scale = self.contentScaleFactor;
    int x = (int)(location.x * scale);
    int y = (int)(location.y * scale);
    
    // Optional: Use pose information for context
    CGFloat altitude = pose.altitude; // Pencil angle from screen
    CGFloat azimuth = pose.azimuth;   // Rotation
    CGFloat zOffset = pose.zOffset;   // Distance from screen
    
    // Send to video driver to show radial menu
    self.driver->ShowRadialMenu(x, y);
    
    self.radialMenuActive = YES;
}

@end
```

#### System Preference Handling

Apple Pencil Pro has user-configurable squeeze actions:
- **Show Color Palette** (default for drawing apps) - We intercept this
- **Switch Eraser** - We can optionally respect this
- **Switch Previous Tool** - We handle via our menu
- **Run Shortcut** - System handles, we don't get the event
- **Ignore** - No squeeze functionality

```objc
- (BOOL)pencilInteraction:(UIPencilInteraction *)interaction 
        didReceiveSqueeze:(UIPencilInteraction.Squeeze *)squeeze 
    API_AVAILABLE(ios(17.5)) {
    
    // Check user's system preference
    UIPencilPreferredAction preferredAction = 
        [UIPencilInteraction preferredSqueezeAction];
    
    switch (preferredAction) {
        case UIPencilPreferredActionShowColorPalette:
        case UIPencilPreferredActionShowInkAttributes:
            // Perfect! User wants palette - show our radial menu
            if (squeeze.phase == UIPencilInteractionPhaseEnded) {
                [self showRadialMenuAtLocation:/* ... */];
                return YES; // We handled it
            }
            break;
            
        case UIPencilPreferredActionSwitchEraser:
            // User wants quick eraser toggle
            // We can still show menu OR respect system preference
            if (_settings_client.gui.radial_menu_override_system_squeeze) {
                [self showRadialMenuAtLocation:/* ... */];
                return YES;
            }
            return NO; // Let system handle eraser toggle
            
        case UIPencilPreferredActionRunSystemShortcut:
            // System will run shortcut, we don't get this event
            return NO;
            
        case UIPencilPreferredActionIgnore:
        default:
            // No squeeze functionality configured
            return NO;
    }
    
    return NO;
}
```

---

## Fallback Activation Methods

### For Non-Pro Pencils:

| Pencil Model | Activation Method | Implementation |
|--------------|------------------|----------------|
| **2nd Gen** | Double-tap | Use `pencilInteractionDidTap:` delegate method |
| **1st Gen** | UI Button | Floating button on screen (can be repositioned) |
| **USB-C** | UI Button | Floating button on screen (can be repositioned) |

#### Floating Button (1st Gen / USB-C)
```objc
// In ios_wnd.mm

- (void)setupRadialMenuButton {
    // Only show if pencil doesn't support squeeze/double-tap
    if ([PencilDetector supportsSqueeze] || [PencilDetector supportsDoubleTap]) {
        return; // Use gesture instead
    }
    
    UIButton *menuButton = [UIButton buttonWithType:UIButtonTypeCustom];
    menuButton.frame = CGRectMake(20, 100, 50, 50);
    [menuButton setImage:[UIImage systemImageNamed:@"wand.and.stars"] 
                forState:UIControlStateNormal];
    menuButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.5];
    menuButton.layer.cornerRadius = 25;
    menuButton.tintColor = [UIColor whiteColor];
    
    [menuButton addTarget:self 
                   action:@selector(radialMenuButtonTapped:)
         forControlEvents:UIControlEventTouchUpInside];
    
    [self addSubview:menuButton];
    
    // Make draggable
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] 
        initWithTarget:self action:@selector(handleButtonPan:)];
    [menuButton addGestureRecognizer:pan];
}

- (void)radialMenuButtonTapped:(UIButton *)sender {
    // Show menu at current pencil hover position, or button position
    CGPoint location = self.pencilHoverPosition ?: sender.center;
    [self showRadialMenuAtLocation:location];
}
```

---

## Radial Menu Structure

### Tool Hierarchy (Complete Mapping)

#### Level 1: Main Categories (6 segments)
```
        RAIL
         |
   LANDSCAPE - ROAD
         |
    🎯 Center
         |
    WATER - AIR
         |
       TRAM
```

Each segment: 60° (360° / 6)

---

### Level 2 & 3: Complete Tool Tree

#### 1. RAIL Category

**Level 2** (6 segments):
1. **Build Track** → Level 3 (5 tools)
   - Build NS
   - Build X (diagonal)
   - Build EW
   - Build Y (diagonal)
   - Autorail
2. **Stations** → Level 3 (2 tools)
   - Station
   - Waypoint
3. **Infrastructure** (direct actions, no Level 3)
   - Depot
4. **Bridges & Tunnels** → Level 3 (2 tools)
   - Bridge
   - Tunnel
5. **Signals** (opens signal picker dialog)
6. **Tools** → Level 3 (2 tools)
   - Remove Track
   - Convert Rail Type

**Total Rail Tools**: 14 + signal picker

---

#### 2. ROAD Category

**Level 2** (6 segments):
1. **Build Road** → Level 3 (3 tools)
   - Build X
   - Build Y
   - Autoroad
2. **Stations** → Level 3 (3 tools)
   - Bus Station
   - Truck Station
   - Waypoint
3. **Infrastructure** (direct action)
   - Depot
4. **Bridges & Tunnels** → Level 3 (2 tools)
   - Bridge
   - Tunnel
5. **One-Way** (direct toggle, road only)
6. **Tools** → Level 3 (2 tools)
   - Remove Road
   - Convert Road Type

**Total Road Tools**: 12

---

#### 3. TRAM Category

**Level 2** (5 segments, since no one-way for trams):
1. **Build Tram** → Level 3 (3 tools)
   - Build X
   - Build Y
   - Autotram
2. **Stations** → Level 3 (3 tools)
   - Passenger Station
   - Cargo Station
   - Waypoint
3. **Infrastructure** (direct action)
   - Depot
4. **Bridges & Tunnels** → Level 3 (2 tools)
   - Bridge
   - Tunnel
5. **Tools** → Level 3 (2 tools)
   - Remove Tram
   - Convert Tram Type

**Total Tram Tools**: 11

---

#### 4. WATER Category

**Level 2** (3 segments):
1. **Stations & Stops** → Level 3 (3 tools)
   - Dock (ship station)
   - Depot
   - Buoy (waypoint)
2. **Waterways** → Level 3 (3 tools)
   - Canal
   - Lock
   - Aqueduct (bridge)
3. **Tools** (direct action)
   - River (scenario editor only)

**Total Water Tools**: 7

---

#### 5. AIR Category

**Level 2** (2 segments):
1. **Build** (opens airport picker)
2. **Remove** (direct action)

**Total Air Tools**: 2 (+ airport type picker)

---

#### 6. LANDSCAPE Category

**Level 2** (4 segments):
1. **Terraform** → Level 3 (3 tools)
   - Raise Land
   - Lower Land
   - Level Land
2. **Vegetation** (direct action)
   - Plant Trees (opens tree picker)
3. **Objects** → Level 3 (3 tools)
   - Place Sign
   - Place Object (opens object picker)
   - Buy Land
4. **Demolish** (direct action)

**Total Landscape Tools**: 8

---

### Flexibility: No Hard 3-Level Limit

Based on your feedback, we're not artificially limiting to 3 levels. However, the current tool structure naturally fits within 3 levels:

- **Level 1**: 6 main categories
- **Level 2**: 3-6 tool groups per category
- **Level 3**: 2-5 individual tools per group

**Deepest path**: Rail → Build Track → Autorail (3 levels) ✓

This depth provides:
- **Quick access**: Common tools 2 hovers away
- **Organization**: Related tools grouped logically
- **Discoverability**: Clear hierarchy

If future tools require Level 4, the architecture supports it.

---

## Visual Design Specifications

### Level 1 Design (Main Categories)

```
Radius: 100-140px from center
Segment Arc: 60° each
Icon Size: 56x56px
Label: Below icon, 12pt semibold
Background: Semi-transparent (60% opacity)
Highlight Color: Category-specific

Category Colors:
• Rail:      #E67E22 (orange)
• Road:      #7F8C8D (gray)
• Tram:      #3498DB (light blue)
• Water:     #2980B9 (blue)
• Air:       #5DADE2 (sky blue)
• Landscape: #27AE60 (green)
```

### Level 2 Design (Tool Groups)

```
Radius: 160-220px from center
Segment Arc: Variable (depending on # of segments)
Icon Size: 40x40px
Label: Small text, 10pt regular
Level 1 State: Shrinks to 60px radius, 50% opacity
Animation: 200ms ease-in-out
```

### Level 3 Design (Individual Tools)

```
Radius: 240-300px from center
Segment Arc: Variable
Icon Size: 36x36px
Label: Abbreviated, 9pt regular
Level 2 State: Shrinks to 100px radius, 50% opacity
Animation: 200ms ease-in-out
```

### Center Indicator

```
Always visible at pencil position
Size: 20x20px circle
Color: White with subtle shadow
Purpose: Visual anchor point
```

---

## Hover Navigation System

### State Machine

```
States:
1. DORMANT: Menu not visible
2. LEVEL_1_ACTIVE: Showing main categories
3. LEVEL_2_ACTIVE: Showing tool groups
4. LEVEL_3_ACTIVE: Showing individual tools
5. TRANSITIONING: Animation between levels

Transitions:
DORMANT → LEVEL_1_ACTIVE: Squeeze gesture (or button tap)
LEVEL_1_ACTIVE → LEVEL_2_ACTIVE: Hover over category
LEVEL_2_ACTIVE → LEVEL_1_ACTIVE: Hover back to center/Level 1
LEVEL_2_ACTIVE → LEVEL_3_ACTIVE: Hover over tool group (if has Level 3)
LEVEL_3_ACTIVE → LEVEL_2_ACTIVE: Hover back to Level 2
ANY_STATE → DORMANT: Tap to select, or pencil lift
```

### Hover Detection

```objc
// In ios_radial_menu.mm

typedef NS_ENUM(NSInteger, RadialMenuLevel) {
    RadialMenuLevel_Dormant = 0,
    RadialMenuLevel_1,
    RadialMenuLevel_2,
    RadialMenuLevel_3
};

@interface RadialMenu : NSObject
@property (nonatomic, assign) RadialMenuLevel currentLevel;
@property (nonatomic, assign) CGPoint centerPoint;
@property (nonatomic, assign) int hoveredSegmentL1;
@property (nonatomic, assign) int hoveredSegmentL2;
@property (nonatomic, assign) int hoveredSegmentL3;

- (void)updateHoverPosition:(CGPoint)position;
- (int)getSegmentAtPosition:(CGPoint)position forLevel:(RadialMenuLevel)level;
- (void)transitionToLevel:(RadialMenuLevel)newLevel;
@end

@implementation RadialMenu

- (void)updateHoverPosition:(CGPoint)position {
    CGFloat dx = position.x - self.centerPoint.x;
    CGFloat dy = position.y - self.centerPoint.y;
    CGFloat distance = sqrt(dx*dx + dy*dy);
    CGFloat angle = atan2(dy, dx) + M_PI; // 0 to 2π
    
    // Determine which level the hover is in
    if (distance < 60 && self.currentLevel > RadialMenuLevel_1) {
        // Hovering center - go back one level
        [self transitionToLevel:self.currentLevel - 1];
    }
    else if (distance >= 100 && distance < 140 && 
             self.currentLevel == RadialMenuLevel_1) {
        // Hovering Level 1 segment
        int segment = (int)(angle / (M_PI / 3)); // 6 segments
        if (segment != self.hoveredSegmentL1) {
            self.hoveredSegmentL1 = segment;
            [self highlightSegment:segment atLevel:RadialMenuLevel_1];
        }
    }
    else if (distance >= 160 && distance < 220 && 
             self.currentLevel == RadialMenuLevel_2) {
        // Hovering Level 2 segment
        int segment = [self getSegmentAtPosition:position forLevel:RadialMenuLevel_2];
        if (segment != self.hoveredSegmentL2) {
            self.hoveredSegmentL2 = segment;
            
            // Check if this segment has Level 3
            if ([self segmentHasLevel3:segment inCategory:self.hoveredSegmentL1]) {
                [self transitionToLevel:RadialMenuLevel_3];
            }
        }
    }
    // ... continue for Level 3
}

@end
```

---

## Context-Aware Tool Availability

### Hide Unavailable Tools

```cpp
// In ios_radial_menu.cpp

struct ToolAvailability {
    static bool ShouldShowRailCategory() {
        return CanBuildVehicleInfrastructure(VEH_TRAIN);
    }
    
    static bool ShouldShowRoadCategory() {
        return CanBuildVehicleInfrastructure(VEH_ROAD, RTT_ROAD);
    }
    
    static bool ShouldShowTramCategory() {
        return CanBuildVehicleInfrastructure(VEH_ROAD, RTT_TRAM);
    }
    
    static bool ShouldShowWaterCategory() {
        return CanBuildVehicleInfrastructure(VEH_SHIP);
    }
    
    static bool ShouldShowAirCategory() {
        return CanBuildVehicleInfrastructure(VEH_AIRCRAFT);
    }
    
    static bool ShouldShowOneWayRoad() {
        return RoadTypeIsRoad(_cur_roadtype);
    }
    
    static bool ShouldShowPlaceObject() {
        return ObjectClass::GetUIClassCount() > 0;
    }
    
    static bool ShouldShowRiver() {
        return _game_mode == GM_EDITOR;
    }
};

// Dynamically build menu based on availability
std::vector<ToolCategory> RadialMenu::GetAvailableCategories() {
    std::vector<ToolCategory> categories;
    
    if (ToolAvailability::ShouldShowRailCategory()) 
        categories.push_back(TOOL_CATEGORY_RAIL);
    if (ToolAvailability::ShouldShowRoadCategory()) 
        categories.push_back(TOOL_CATEGORY_ROAD);
    if (ToolAvailability::ShouldShowTramCategory()) 
        categories.push_back(TOOL_CATEGORY_TRAM);
    if (ToolAvailability::ShouldShowWaterCategory()) 
        categories.push_back(TOOL_CATEGORY_WATER);
    if (ToolAvailability::ShouldShowAirCategory()) 
        categories.push_back(TOOL_CATEGORY_AIR);
    // Landscape always available
    categories.push_back(TOOL_CATEGORY_LANDSCAPE);
    
    // Redistribute angles if fewer than 6 categories
    // E.g., if only 3 categories, use 120° segments instead of 60°
    
    return categories;
}
```

### Tile-Based Context (Advanced)

**Future Enhancement**: Rotate menu to prioritize relevant category based on tile under pencil.

```cpp
ToolCategory RadialMenu::GetContextualPrimaryCategory(TileIndex tile) {
    if (IsTileType(tile, MP_RAILWAY)) return TOOL_CATEGORY_RAIL;
    if (IsNormalRoadTile(tile)) {
        if (RoadTypeIsTram(_cur_roadtype)) return TOOL_CATEGORY_TRAM;
        return TOOL_CATEGORY_ROAD;
    }
    if (IsTileType(tile, MP_WATER)) return TOOL_CATEGORY_WATER;
    if (IsTileType(tile, MP_STATION)) {
        StationType st_type = GetStationType(tile);
        if (st_type == STATION_AIRPORT) return TOOL_CATEGORY_AIR;
        if (st_type == STATION_DOCK) return TOOL_CATEGORY_WATER;
        if (st_type == STATION_RAIL) return TOOL_CATEGORY_RAIL;
        if (st_type == STATION_BUS || st_type == STATION_TRUCK) {
            if (IsTramStop(tile)) return TOOL_CATEGORY_TRAM;
            return TOOL_CATEGORY_ROAD;
        }
    }
    return TOOL_CATEGORY_LANDSCAPE; // Default for empty land
}

// When showing menu, rotate so contextual category is at "12 o'clock"
void RadialMenu::ShowAtPosition(CGPoint position, TileIndex tile) {
    this->centerPoint = position;
    
    if (_settings_client.gui.radial_menu_context_aware) {
        ToolCategory primary = GetContextualPrimaryCategory(tile);
        this->rotationOffset = CalculateRotationForPrimary(primary);
    } else {
        this->rotationOffset = 0; // Fixed layout
    }
    
    [self transitionToLevel:RadialMenuLevel_1];
}
```

---

## Settings & Configuration

### New Settings

```cpp
// In settings_type.h

struct GUISettings {
    // ... existing settings ...
    
    // Apple Pencil Radial Menu
    bool use_radial_menu;                      ///< Enable radial menu for Apple Pencil
    bool radial_menu_context_aware;             ///< Rotate menu based on tile context
    bool radial_menu_override_system_squeeze;   ///< Override system squeeze preference
    uint8 radial_menu_animation_speed;          ///< 0=instant, 1=fast, 2=normal, 3=slow
    uint8 radial_menu_activation_method;        ///< 0=auto-detect, 1=squeeze, 2=double-tap, 3=button
    bool radial_menu_show_labels;               ///< Show text labels on tools
    uint8 radial_menu_size_scale;               ///< 50-150% size scaling
};
```

### Settings UI

```
┌─────────────────────────────────────────────────────────┐
│  Settings → Interface → Apple Pencil                    │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Radial Build Menu                                      │
│  ☑ Enable radial menu                                  │
│                                                         │
│  Activation Method:                                     │
│    ● Auto-detect based on Apple Pencil model           │
│    ○ Squeeze gesture (Pro only)                        │
│    ○ Double-tap (2nd Gen / Pro)                        │
│    ○ Floating button (All models)                      │
│                                                         │
│  Menu Behavior:                                         │
│  ☑ Context-aware positioning                           │
│      (Rotate menu based on tile under pencil)          │
│                                                         │
│  ☑ Override system squeeze preference                  │
│      (Use squeeze for radial menu even if system       │
│       configured for other action)                     │
│                                                         │
│  Animation Speed:                                       │
│    [═══════●═══════] Normal                            │
│     Instant        Slow                                │
│                                                         │
│  Appearance:                                            │
│  ☑ Show text labels                                    │
│                                                         │
│  Size Scale:                                            │
│    [════●═════════] 100%                               │
│     50%           150%                                 │
│                                                         │
│  [Configure Pencil Model...]                           │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

---

## Implementation Roadmap

### Phase 1: Core Infrastructure (Week 1-2)
- [ ] Apple Pencil generation detection
- [ ] UIPencilInteraction setup for squeeze/double-tap
- [ ] Basic radial menu rendering (Level 1 only)
- [ ] Hover position tracking
- [ ] Settings integration

### Phase 2: Multi-Level Navigation (Week 3)
- [ ] Level 2 expansion/collapse
- [ ] Level 3 for complex categories (Rail, Road, Tram)
- [ ] Animation system
- [ ] Hover-based navigation logic
- [ ] Tool selection and activation

### Phase 3: Tool Integration (Week 4)
- [ ] Connect to existing toolbar commands
- [ ] Rail tools (14 tools)
- [ ] Road tools (12 tools)
- [ ] Tram tools (11 tools)
- [ ] Water tools (7 tools)
- [ ] Air tools (2 tools)
- [ ] Landscape tools (8 tools)

### Phase 4: Context Awareness (Week 5)
- [ ] Tool availability checking
- [ ] Hide unavailable categories/tools
- [ ] Tile-based context detection
- [ ] Auto-rotation based on context

### Phase 5: Polish & Optimization (Week 6)
- [ ] Haptic feedback tuning
- [ ] Icon refinement
- [ ] Performance optimization
- [ ] User testing
- [ ] Bug fixes

---

## Technical Implementation Files

### New Files

```
src/video/ios/
├── ios_radial_menu.h          // RadialMenu class
├── ios_radial_menu.mm         // Implementation
├── ios_pencil_detector.h      // Generation detection
├── ios_pencil_detector.mm     // Implementation
└── ios_pencil_gesture.mm      // Squeeze/tap handling

src/widgets/
└── radial_menu_sprites.h      // Icon mappings
```

### Integration Points

```cpp
// VideoDriver_iOS modifications

class VideoDriver_iOS {
public:
    void ShowRadialMenu(int x, int y, TileIndex tile);
    void HideRadialMenu();
    void UpdateRadialMenuHover(int x, int y);
    void SelectRadialMenuTool(ToolID tool);
    
private:
    RadialMenu *radial_menu = nullptr;
    bool radial_menu_active = false;
};
```

---

## Performance Requirements

- **Render Budget**: < 2ms for menu rendering (60fps)
- **Input Latency**: < 10ms from squeeze to menu display
- **Animation**: Smooth 60fps transitions
- **Memory**: < 2MB for menu textures and state
- **Battery Impact**: Minimal (haptics are brief, rendering is efficient)

---

## Accessibility

1. **VoiceOver**: Announce tool names when hovering
2. **Dynamic Type**: Scale text labels with system settings
3. **Reduce Motion**: Instant transitions if user has motion reduction enabled
4. **High Contrast**: Increase opacity and borders in high contrast mode
5. **Color Blind Modes**: Don't rely solely on color for categorization

---

## Summary

This radial menu system leverages the Apple Pencil Pro's **squeeze gesture** as the primary activation method, providing instant access to 50+ building tools through an intuitive 3-level hierarchy. The system gracefully adapts to all Apple Pencil generations, ensuring all users can benefit from streamlined tool access.

**Key Features:**
- **Primary**: Squeeze gesture (Apple Pencil Pro)
- **Fallback**: Double-tap (2nd Gen), Button (1st Gen/USB-C)
- **Hover Navigation**: Smooth level transitions
- **Context-Aware**: Hide unavailable tools, optional tile-based rotation
- **Flexible Depth**: No artificial 3-level limit (currently fits within 3)
- **Haptic Feedback**: Tactile confirmation on Pro models

**Benefits:**
- Minimal screen clutter
- Fast tool access (2-3 hover movements)
- Natural pencil-based workflow
- Respects system preferences
- Professional precision

---

## Next Steps

1. ✅ Complete design documentation
2. Review design with user/team
3. Create visual mockups/prototypes
4. Begin Phase 1 implementation
5. Test on all Apple Pencil models
6. Iterate based on user feedback
