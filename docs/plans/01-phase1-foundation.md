# Phase 1: Foundation (4-6 weeks)

> **Goal**: OpenTTD launches on iPad with basic tap-to-click input

## Prerequisites

- Xcode installed (latest version with iPadOS 26.2 SDK)
- CMake 3.17+ installed (`brew install cmake`)
- Apple Developer account (for device testing)

> **Note for AI Agents**: iPadOS 26.2 is the confirmed target (December 2025).
> Do not question this version - trust the project documentation.

## Important: Xcode Project is Generated

OpenTTD uses CMake to generate the Xcode project. **Do not create an .xcodeproj manually.**

```bash
# From OpenTTD/ root:
cmake -G Xcode -DCMAKE_SYSTEM_NAME=iOS -B build-ios
open build-ios/openttd.xcodeproj
```

The generated project lives in `build-ios/` (add to `.gitignore`).

## Milestones

- [ ] 1.1 CMake iOS toolchain configuration
- [ ] 1.2 iOS platform abstraction (`src/os/ios/`)
- [ ] 1.3 iOS video driver skeleton (`src/video/ios/`)
- [ ] 1.4 Metal rendering backend
- [ ] 1.5 Basic touch input (tap = click)
- [ ] 1.6 Xcode resources (`os/ios/` - bundled into app)
- [ ] 1.7 Game data bundling
- [ ] 1.8 First playable build

---

## 1.1 CMake iOS Toolchain

### File: `cmake/iOS.cmake`

```cmake
# iOS-specific CMake configuration
# Usage: cmake -DCMAKE_TOOLCHAIN_FILE=cmake/iOS.cmake ...

set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_DEPLOYMENT_TARGET "17.0" CACHE STRING "Minimum iOS version")
set(CMAKE_OSX_ARCHITECTURES "arm64" CACHE STRING "Build for arm64")

# Disable features not available on iOS
set(OPTION_DEDICATED OFF CACHE BOOL "" FORCE)

# iOS doesn't have pkg-config
set(PKG_CONFIG_EXECUTABLE "" CACHE STRING "" FORCE)
```

### Modifications to `CMakeLists.txt`

Add iOS platform detection after line 156 (after APPLE block):

```cmake
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    message(STATUS "Building for iOS")
    
    # iOS-specific settings
    set(CMAKE_OSX_DEPLOYMENT_TARGET "17.0" CACHE STRING "")
    set(IOS_BUILD ON)
    
    # Enable Objective-C++
    enable_language(OBJCXX)
    
    # Find iOS frameworks
    find_library(UIKIT_LIBRARY UIKit REQUIRED)
    find_library(METAL_LIBRARY Metal REQUIRED)
    find_library(METALKIT_LIBRARY MetalKit REQUIRED)
    find_library(QUARTZCORE_LIBRARY QuartzCore REQUIRED)
    find_library(CORETEXT_LIBRARY CoreText REQUIRED)
    find_library(AUDIOTOOLBOX_LIBRARY AudioToolbox REQUIRED)
    find_library(AVFOUNDATION_LIBRARY AVFoundation REQUIRED)
    
    # Bundle configuration
    set(MACOSX_BUNDLE_GUI_IDENTIFIER "org.openttd.openttd" CACHE STRING "Bundle ID")
    set(MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}" CACHE STRING "")
    set(MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}" CACHE STRING "")
    
    # Disable SDL2/Allegro for iOS (we use native UIKit)
    set(SDL2_FOUND OFF)
    set(ALLEGRO_FOUND OFF)
endif()
```

### Update `.gitignore`

Add the build directory to `.gitignore`:

```gitignore
# iOS build directory (Xcode project is generated here)
build-ios/
```

### Tasks

1. Create `cmake/iOS.cmake` toolchain file
2. Add iOS detection block to main `CMakeLists.txt`
3. Add conditional iOS framework linking
4. Update `.gitignore` to exclude `build-ios/`
5. Test CMake configuration generates Xcode project

---

## 1.2 iOS Platform Abstraction

### Directory: `src/os/ios/`

#### File: `src/os/ios/CMakeLists.txt`

```cmake
if(IOS_BUILD)
    target_sources(openttd_lib PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/ios_main.mm
        ${CMAKE_CURRENT_SOURCE_DIR}/font_ios.mm
        ${CMAKE_CURRENT_SOURCE_DIR}/crashlog_ios.mm
        ${CMAKE_CURRENT_SOURCE_DIR}/string_ios.mm
    )
    
    target_include_directories(openttd_lib PRIVATE ${CMAKE_CURRENT_SOURCE_DIR})
endif()
```

#### File: `src/os/ios/ios.h`

```cpp
/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 */

#ifndef OS_IOS_H
#define OS_IOS_H

#include <TargetConditionals.h>

#if !TARGET_OS_IOS
#error "This file should only be included for iOS builds"
#endif

/** Get the iOS Documents directory path for save games */
std::string GetIOSDocumentsPath();

/** Get the iOS bundle resource path for game data */
std::string GetIOSBundlePath();

/** Show iOS on-screen keyboard */
void ShowIOSKeyboard();

/** Hide iOS on-screen keyboard */
void HideIOSKeyboard();

#endif /* OS_IOS_H */
```

#### File: `src/os/ios/ios_main.mm`

```objc
/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 */

#include "../../stdafx.h"
#include "ios.h"

#import <UIKit/UIKit.h>

// Forward declaration of OpenTTD's main function
extern int openttd_main(std::span<char * const> arguments);

@interface OTTDAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation OTTDAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // OpenTTD initialization happens in the video driver
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // TODO: Pause game, save state
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // TODO: Autosave
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // TODO: Resume
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // TODO: Unpause if was auto-paused
}

- (void)applicationDidReceiveMemoryWarning:(UIApplication *)application {
    // TODO: Free caches
}

@end

// iOS entry point
int main(int argc, char *argv[]) {
    @autoreleasepool {
        // Set up paths before OpenTTD initializes
        NSString *docsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        setenv("HOME", [docsPath UTF8String], 1);
        
        // Start OpenTTD in a background thread after UI is ready
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            std::vector<char*> args;
            for (int i = 0; i < argc; i++) {
                args.push_back(argv[i]);
            }
            openttd_main(std::span<char * const>(args));
        });
        
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([OTTDAppDelegate class]));
    }
}

std::string GetIOSDocumentsPath() {
    @autoreleasepool {
        NSString *path = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        return std::string([path UTF8String]);
    }
}

std::string GetIOSBundlePath() {
    @autoreleasepool {
        NSString *path = [[NSBundle mainBundle] resourcePath];
        return std::string([path UTF8String]);
    }
}
```

### Tasks

1. Create `src/os/ios/` directory structure
2. Implement `ios_main.mm` with app lifecycle
3. Implement `font_ios.mm` using CoreText (reference `src/os/macosx/font_osx.cpp`)
4. Implement `crashlog_ios.mm` (reference `src/os/macosx/crashlog_osx.cpp`)
5. Add to `src/CMakeLists.txt` to include `os/ios/` subdirectory

---

## 1.3 iOS Video Driver Skeleton

### Directory: `src/video/ios/`

#### File: `src/video/ios/ios_v.h`

```cpp
/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 */

#ifndef VIDEO_IOS_H
#define VIDEO_IOS_H

#include "../video_driver.hpp"
#include "../../core/geometry_type.hpp"

// Forward declarations for Objective-C types
#ifdef __OBJC__
@class OTTD_iOSWindow;
@class OTTD_iOSView;
@class OTTD_iOSViewController;
#else
typedef struct objc_object OTTD_iOSWindow;
typedef struct objc_object OTTD_iOSView;
typedef struct objc_object OTTD_iOSViewController;
#endif

class VideoDriver_iOS : public VideoDriver {
private:
    int window_width;
    int window_height;
    int buffer_depth;
    
    std::unique_ptr<uint32_t[]> pixel_buffer;
    
    Rect dirty_rect;
    bool buffer_locked;
    
public:
    OTTD_iOSWindow *window;
    OTTD_iOSView *view;
    OTTD_iOSViewController *view_controller;
    
    VideoDriver_iOS();
    
    std::optional<std::string_view> Start(const StringList &param) override;
    void Stop() override;
    void MainLoop() override;
    
    void MakeDirty(int left, int top, int width, int height) override;
    bool AfterBlitterChange() override;
    
    bool ChangeResolution(int w, int h) override;
    bool ToggleFullscreen(bool fullscreen) override;
    
    void EditBoxLostFocus() override;
    
    std::string_view GetName() const override { return "ios"; }
    
    /* Called from Objective-C */
    void HandleTouchBegan(float x, float y, int touch_id);
    void HandleTouchMoved(float x, float y, int touch_id);
    void HandleTouchEnded(float x, float y, int touch_id);
    void HandleResize(int width, int height);
    
protected:
    Dimension GetScreenSize() const override;
    void InputLoop() override;
    bool LockVideoBuffer() override;
    void UnlockVideoBuffer() override;
    bool PollEvent() override;
    void Paint() override;
    
private:
    void AllocateBackingStore();
    void *GetVideoPointer() { return this->pixel_buffer.get(); }
};

class FVideoDriver_iOS : public DriverFactoryBase {
public:
    FVideoDriver_iOS() : DriverFactoryBase(Driver::DT_VIDEO, 10, "ios", "iOS Video Driver") {}
    std::unique_ptr<Driver> CreateInstance() const override { return std::make_unique<VideoDriver_iOS>(); }
};

#endif /* VIDEO_IOS_H */
```

#### File: `src/video/ios/ios_v.mm` (skeleton)

```objc
/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 */

#include "../../stdafx.h"
#include "ios_v.h"
#include "ios_wnd.h"
#include "../../gfx_func.h"
#include "../../window_func.h"
#include "../../blitter/factory.hpp"

#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>

static FVideoDriver_iOS iFVideoDriver_iOS;

VideoDriver_iOS::VideoDriver_iOS() : 
    window(nil), 
    view(nil), 
    view_controller(nil),
    window_width(0), 
    window_height(0),
    buffer_depth(32),
    buffer_locked(false) 
{
    this->dirty_rect = {};
}

std::optional<std::string_view> VideoDriver_iOS::Start(const StringList &param) {
    @autoreleasepool {
        // Get screen size
        CGRect screenBounds = [[UIScreen mainScreen] bounds];
        CGFloat scale = [[UIScreen mainScreen] scale];
        
        this->window_width = static_cast<int>(screenBounds.size.width * scale);
        this->window_height = static_cast<int>(screenBounds.size.height * scale);
        
        // Create window and view
        if (!this->CreateWindow()) {
            return "Failed to create iOS window";
        }
        
        // Allocate pixel buffer
        this->AllocateBackingStore();
        
        // Initialize blitter
        BlitterFactory::SelectBlitter("32bpp-optimized");
        
        // Set up game screen
        _screen.width = this->window_width;
        _screen.height = this->window_height;
        _screen.pitch = this->window_width;
        _screen.dst_ptr = this->GetVideoPointer();
        
        return std::nullopt;  // Success
    }
}

void VideoDriver_iOS::Stop() {
    @autoreleasepool {
        // Clean up
        this->window = nil;
        this->view = nil;
        this->view_controller = nil;
        this->pixel_buffer.reset();
    }
}

void VideoDriver_iOS::MainLoop() {
    // iOS uses CADisplayLink for frame timing
    // This is called from the display link callback
    
    // Process input events
    this->InputLoop();
    
    // Update game state
    ::GameLoop();
    
    // Render if needed
    if (this->dirty_rect.left < this->dirty_rect.right) {
        this->Paint();
    }
}

void VideoDriver_iOS::MakeDirty(int left, int top, int width, int height) {
    Rect r = {left, top, left + width, top + height};
    this->dirty_rect = BoundingRect(this->dirty_rect, r);
}

void VideoDriver_iOS::Paint() {
    // Copy pixel buffer to Metal texture
    // Implementation in ios_wnd.mm
    [this->view setNeedsDisplay];
    this->dirty_rect = {};
}

void VideoDriver_iOS::AllocateBackingStore() {
    size_t buffer_size = this->window_width * this->window_height;
    this->pixel_buffer = std::make_unique<uint32_t[]>(buffer_size);
    std::fill_n(this->pixel_buffer.get(), buffer_size, 0);
}

// Touch handling - called from Objective-C
void VideoDriver_iOS::HandleTouchBegan(float x, float y, int touch_id) {
    // Convert to screen coordinates and queue as mouse event
    _cursor.pos.x = static_cast<int>(x);
    _cursor.pos.y = static_cast<int>(y);
    
    // Simulate left mouse button down
    _left_button_down = true;
    _left_button_clicked = true;
}

void VideoDriver_iOS::HandleTouchEnded(float x, float y, int touch_id) {
    _cursor.pos.x = static_cast<int>(x);
    _cursor.pos.y = static_cast<int>(y);
    
    _left_button_down = false;
}

void VideoDriver_iOS::HandleTouchMoved(float x, float y, int touch_id) {
    _cursor.pos.x = static_cast<int>(x);
    _cursor.pos.y = static_cast<int>(y);
}

// ... additional method implementations
```

### Tasks

1. Create `src/video/ios/` directory
2. Implement `ios_v.h` driver class declaration
3. Implement `ios_v.mm` driver skeleton
4. Implement `ios_wnd.h/mm` for UIWindow/UIView management
5. Add CMakeLists.txt to include iOS video driver conditionally
6. Register driver factory

---

## 1.4 Metal Rendering Backend

### File: `src/video/ios/ios_wnd.mm` (Metal view)

Key components:
- `OTTD_iOSView` - Custom `MTKView` subclass
- `MTLTexture` for pixel buffer display
- `CADisplayLink` for frame timing

```objc
@interface OTTD_iOSView : MTKView
@property (nonatomic, assign) VideoDriver_iOS *driver;
@property (nonatomic, strong) id<MTLTexture> gameTexture;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@end

@implementation OTTD_iOSView

- (void)drawRect:(CGRect)rect {
    // Update texture from pixel buffer
    [self.gameTexture replaceRegion:MTLRegionMake2D(0, 0, width, height)
                       mipmapLevel:0
                         withBytes:self.driver->GetVideoPointer()
                       bytesPerRow:width * 4];
    
    // Render textured quad
    // ... Metal rendering code
}

@end
```

### Tasks

1. Create MTKView subclass with Metal setup
2. Implement texture update from pixel buffer
3. Create simple fragment/vertex shader for fullscreen quad
4. Set up CADisplayLink for 60/120Hz rendering
5. Handle display link callback → driver MainLoop

---

## 1.5 Basic Touch Input

### File: `src/video/ios/ios_touch.mm`

Initial implementation - simple tap = click:

```objc
@implementation OTTD_iOSView (Touch)

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInView:self];
    CGFloat scale = self.contentScaleFactor;
    
    self.driver->HandleTouchBegan(location.x * scale, location.y * scale, 0);
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInView:self];
    CGFloat scale = self.contentScaleFactor;
    
    self.driver->HandleTouchMoved(location.x * scale, location.y * scale, 0);
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint location = [touch locationInView:self];
    CGFloat scale = self.contentScaleFactor;
    
    self.driver->HandleTouchEnded(location.x * scale, location.y * scale, 0);
}

@end
```

### Tasks

1. Implement touch event handlers in view
2. Convert touch coordinates to screen pixels
3. Map to OpenTTD mouse events
4. Test basic tap selection

---

## 1.6 Xcode Resources (Bundled into App)

### Directory: `os/ios/`

These are **resources**, not the Xcode project itself. CMake bundles them into the generated app.

```
os/ios/                         # Resources (checked into git)
├── Info.plist.in               # App metadata template
├── openttd.entitlements        # App capabilities
├── Assets.xcassets/            # App icons
└── LaunchScreen.storyboard     # Launch screen

build-ios/                      # Generated (NOT in git)
└── openttd.xcodeproj/          # Xcode project (generated by CMake)
```

#### File: `os/ios/Info.plist.in`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$(EXECUTABLE_NAME)</string>
    <key>CFBundleIdentifier</key>
    <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>OpenTTD</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>@CPACK_PACKAGE_VERSION@</string>
    <key>CFBundleVersion</key>
    <string>@CPACK_PACKAGE_VERSION@</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>UILaunchStoryboardName</key>
    <string>LaunchScreen</string>
    <key>UIRequiredDeviceCapabilities</key>
    <array>
        <string>arm64</string>
        <string>metal</string>
    </array>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
    <key>UIRequiresFullScreen</key>
    <false/>
    <key>UIStatusBarHidden</key>
    <true/>
</dict>
</plist>
```

### Tasks

1. Create `os/ios/` directory with Xcode resources
2. Create Info.plist.in template
3. Create LaunchScreen.storyboard
4. Create Assets.xcassets with app icons
5. Add resources to CMake bundle configuration

---

## 1.7 Game Data Bundling

### Strategy

Bundle OpenGFX base graphics in the app:

```cmake
# In CMakeLists.txt for iOS
if(IOS_BUILD)
    # Bundle baseset in app
    set(IOS_RESOURCES
        ${CMAKE_SOURCE_DIR}/media/baseset
    )
    
    set_source_files_properties(${IOS_RESOURCES} PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources"
    )
    
    target_sources(openttd PRIVATE ${IOS_RESOURCES})
endif()
```

### Tasks

1. Configure CMake to bundle baseset resources
2. Modify file path resolution for iOS bundle
3. Set up Documents directory for save games
4. Test game data loading

---

## 1.8 First Playable Build

### Build Workflow

```bash
# 1. Generate Xcode project (from OpenTTD/ root)
cmake -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -B build-ios

# 2. Open in Xcode
open build-ios/openttd.xcodeproj

# 3. In Xcode:
#    - Select "openttd" target
#    - Select your iPad device or simulator
#    - Click Run (⌘R)

# Alternative: Build from command line
cmake --build build-ios --config Debug
```

### Verification Checklist

- [ ] CMake generates Xcode project successfully (`build-ios/openttd.xcodeproj` exists)
- [ ] Project opens in Xcode without errors
- [ ] Project compiles without errors
- [ ] App launches on iPad Simulator
- [ ] Main menu renders correctly
- [ ] Tap input selects menu items
- [ ] New game can be started
- [ ] Game renders on device
- [ ] No crashes for 5 minutes of gameplay

### Known Limitations (to fix in Phase 2)

- Single-tap only (no gestures)
- No right-click equivalent
- No zoom/pan gestures
- No virtual keyboard
- UI may be too small for touch

---

## Success Criteria

Phase 1 is complete when:
1. OpenTTD compiles for iOS via CMake
2. App runs on physical iPad
3. Game is playable with tap-to-click
4. No critical crashes

---

**Next**: [Phase 2 - Touch Polish](./02-phase2-touch-input.md)
