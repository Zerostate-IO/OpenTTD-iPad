/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <https://www.gnu.org/licenses/old-licenses/gpl-2.0>.
 */

/** @file ios_v.mm Code related to the iOS video driver. */

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

#if TARGET_OS_IOS

#include "../../stdafx.h"
#include "../../openttd.h"
#include "../../debug.h"
#include "../../error_func.h"
#include "../../core/geometry_func.hpp"
#include "../../core/math_func.hpp"
#include "ios_v.h"
#include "ios_wnd.h"
#include "../../blitter/factory.hpp"
#include "../../framerate_type.h"
#include "../../window_func.h"
#include "../../gfx_func.h"
#include "../../thread.h"
#include "../../progress.h"
#include "../../company_func.h"

#include <thread>
#include <chrono>

#import <UIKit/UIKit.h>

bool _ios_video_started = false;

// --------------------------------------------------------------------------------
// VideoDriver_iOS Implementation
// --------------------------------------------------------------------------------

VideoDriver_iOS::VideoDriver_iOS(bool uses_hardware_acceleration)
	: VideoDriver(uses_hardware_acceleration)
{
	this->setup         = false;
	this->buffer_locked = false;
	this->refresh_sys_sprites = true;
	this->window    = nil;
	this->viewController = nil;
	this->metalView = nil;
	this->displayLink = nil;
	this->dirty_rect = {};
	this->touch_is_dragging = false;
	this->touch_start_x = 0;
	this->touch_start_y = 0;
	this->active_touch_id = 0;
}

void VideoDriver_iOS::Stop()
{
	if (!_ios_video_started) return;

    if (this->displayLink) {
        [this->displayLink invalidate];
        this->displayLink = nil;
    }

	iOSExitApplication();

	/* Release window mode resources */
	this->metalView = nil;
	this->viewController = nil;
	this->window = nil;

	_ios_video_started = false;
}

std::optional<std::string_view> VideoDriver_iOS::Initialize()
{
	if (_ios_video_started) return "Already started";
	_ios_video_started = true;

	if (!iOSSetupApplication()) return std::nullopt;

	this->UpdateAutoResolution();
	this->orig_res = _cur_resolution;

	return std::nullopt;
}

void VideoDriver_iOS::MakeDirty(int left, int top, int width, int height)
{
	Rect r = {left, top, left + width, top + height};
	this->dirty_rect = BoundingRect(this->dirty_rect, r);
}

void VideoDriver_iOS::MainLoop()
{
	NSLog(@"VideoDriver_iOS::MainLoop started, is_game_threaded=%d", this->is_game_threaded);
	
	// Initialize timing for the draw loop
	this->next_game_tick = std::chrono::steady_clock::now();
	this->next_draw_tick = std::chrono::steady_clock::now();
	
	// Start the game thread (handles game logic independently)
	this->StartGameThread();
	NSLog(@"VideoDriver_iOS::MainLoop - game thread started");
	
	// Mark driver as ready for tick processing
	this->ready_for_tick = true;
	NSLog(@"VideoDriver_iOS::MainLoop - ready for tick, display link will drive Tick() on main thread");
	
	// On iOS, unlike macOS's [NSApp run], we don't have a blocking main run loop.
	// The display link (CADisplayLink) fires on the main thread and drives Tick().
	// This background thread just waits for the exit signal.
	// This pattern ensures:
	// 1. Game logic runs on game thread (via StartGameThread)
	// 2. Drawing/UI runs on main thread (via display link calling Tick)
	// 3. This thread just monitors for exit
	@autoreleasepool {
		NSLog(@"VideoDriver_iOS::MainLoop waiting for exit, _exit_game=%d", (int)_exit_game.load());
		
		while (!_exit_game.load()) {
			// Sleep briefly to avoid busy-waiting
			std::this_thread::sleep_for(std::chrono::milliseconds(100));
		}
		
		NSLog(@"VideoDriver_iOS::MainLoop exiting, _exit_game=%d", (int)_exit_game.load());
	}
	
	// Mark as not ready and stop the game thread
	this->ready_for_tick = false;
	this->StopGameThread();
	NSLog(@"VideoDriver_iOS::MainLoop - game thread stopped");
}

bool VideoDriver_iOS::ChangeResolution(int w, int h)
{
	// iOS handles resolution changes automatically via auto-layout / constraints
	// but we might need to update internal buffers
	this->AllocateBackingStore();
	return true;
}

bool VideoDriver_iOS::ToggleFullscreen(bool fullscreen)
{
	// iOS is always fullscreen
	return true;
}

void VideoDriver_iOS::ToggleVsync(bool vsync)
{
    if (!this->displayLink) return;
    
    if (vsync) {
        // Normal vsync - respect thermal state for frame rate
        NSProcessInfoThermalState state = [[NSProcessInfo processInfo] thermalState];
        if (state == NSProcessInfoThermalStateSerious || state == NSProcessInfoThermalStateCritical) {
            if (@available(iOS 15.0, *)) {
                this->displayLink.preferredFrameRateRange = CAFrameRateRangeMake(30, 30, 30);
            } else {
                this->displayLink.preferredFramesPerSecond = 30;
            }
        } else {
            if (@available(iOS 15.0, *)) {
                this->displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
            } else {
                this->displayLink.preferredFramesPerSecond = 60;
            }
        }
    } else {
        // No vsync - run as fast as possible (still limited by display)
        if (@available(iOS 15.0, *)) {
            this->displayLink.preferredFrameRateRange = CAFrameRateRangeMake(120, 120, 120);
        } else {
            this->displayLink.preferredFramesPerSecond = 120;
        }
    }
}

void VideoDriver_iOS::ClearSystemSprites()
{
	this->refresh_sys_sprites = true;
}

void VideoDriver_iOS::PopulateSystemSprites()
{
	if (this->refresh_sys_sprites && this->window != nil) {
		// [ this->window refreshSystemSprites ];
		this->refresh_sys_sprites = false;
	}
}

void VideoDriver_iOS::EditBoxLostFocus()
{
	// Hide keyboard?
}

std::vector<int> VideoDriver_iOS::GetListOfMonitorRefreshRates()
{
	if (this->metalView) {
		return { (int)this->metalView.preferredFramesPerSecond };
	}
	return { 60 };
}

void VideoDriver_iOS::MainLoopReal()
{
	// This would be called by the timer/display link in the iOS run loop
	// Since we use CADisplayLink on the main thread, we might not need this
    // unless base VideoDriver expects us to start something.
    // Cocoa driver starts a thread here.
    // We are running on main thread via DisplayLink.
}

bool VideoDriver_iOS::MakeWindow(int width, int height)
{
	this->setup = true;
	NSLog(@"VideoDriver_iOS::MakeWindow called with %dx%d", width, height);

	// On iOS, the window is created by the SceneDelegate (ios_main.mm).
	// We need to dispatch to main thread to create our view controller and integrate.
	__block bool success = false;
	__block VideoDriver_iOS *self = this;
	
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	
	dispatch_async(dispatch_get_main_queue(), ^{
		@autoreleasepool {
			NSLog(@"VideoDriver_iOS: Looking for existing window...");
			// Get the existing window from the key window
			UIWindow *existingWindow = nil;
			NSLog(@"VideoDriver_iOS: Connected scenes count: %lu", (unsigned long)[UIApplication sharedApplication].connectedScenes.count);
			for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
				NSLog(@"VideoDriver_iOS: Scene activation state: %ld", (long)scene.activationState);
				if (scene.activationState == UISceneActivationStateForegroundActive ||
				    scene.activationState == UISceneActivationStateForegroundInactive) {
					NSLog(@"VideoDriver_iOS: Scene windows count: %lu", (unsigned long)scene.windows.count);
					for (UIWindow *win in scene.windows) {
						NSLog(@"VideoDriver_iOS: Window isKeyWindow: %d", win.isKeyWindow);
						if (win.isKeyWindow) {
							existingWindow = win;
							break;
						}
					}
					if (existingWindow) break;
				}
			}
			
			if (!existingWindow) {
				NSLog(@"VideoDriver_iOS: No existing window found, trying first window from any scene");
				// Try getting any window if key window not found yet
				for (UIWindowScene *scene in [UIApplication sharedApplication].connectedScenes) {
					if (scene.windows.count > 0) {
						existingWindow = scene.windows.firstObject;
						NSLog(@"VideoDriver_iOS: Using first window from scene");
						break;
					}
				}
			}
			
			if (!existingWindow) {
				NSLog(@"VideoDriver_iOS: Still no window found!");
				dispatch_semaphore_signal(sem);
				return;
			}
			
			NSLog(@"VideoDriver_iOS: Got existing window: %@", existingWindow);
			self->window = existingWindow;
			
			// Create our view controller
			NSLog(@"VideoDriver_iOS: Creating view controller...");
			self->viewController = [[OTTD_iOSViewController alloc] initWithDriver:self];
			NSLog(@"VideoDriver_iOS: View controller created: %@", self->viewController);
			
			// Access the view to trigger loadView
			NSLog(@"VideoDriver_iOS: Accessing view to trigger loadView...");
			UIView *v = self->viewController.view;
			NSLog(@"VideoDriver_iOS: View loaded: %@", v);
			if ([v isKindOfClass:[OTTD_MetalView class]]) {
				self->metalView = (OTTD_MetalView *)v;
				NSLog(@"VideoDriver_iOS: Metal view set: %@", self->metalView);
			} else {
				NSLog(@"VideoDriver_iOS: View is NOT a MetalView! Class: %@", [v class]);
			}
			
			// Replace the window's root view controller with ours
			NSLog(@"VideoDriver_iOS: Setting root view controller...");
			existingWindow.rootViewController = self->viewController;
			[existingWindow makeKeyAndVisible];
			NSLog(@"VideoDriver_iOS: Window made key and visible");
			
			// Setup DisplayLink on main thread
			self->displayLink = [CADisplayLink displayLinkWithTarget:self->viewController selector:@selector(displayLinkFired:)];
			
			// Initial thermal state check
			NSProcessInfoThermalState state = [[NSProcessInfo processInfo] thermalState];
			if (state == NSProcessInfoThermalStateSerious || state == NSProcessInfoThermalStateCritical) {
				if (@available(iOS 15.0, *)) {
					self->displayLink.preferredFrameRateRange = CAFrameRateRangeMake(30, 30, 30);
				} else {
					self->displayLink.preferredFramesPerSecond = 30;
				}
			} else {
				if (@available(iOS 15.0, *)) {
					self->displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
				} else {
					self->displayLink.preferredFramesPerSecond = 60;
				}
			}
			
			[self->displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
			
			// Observer for thermal state
			[[NSNotificationCenter defaultCenter] addObserverForName:NSProcessInfoThermalStateDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
				NSProcessInfoThermalState thermalState = [[NSProcessInfo processInfo] thermalState];
				if (thermalState == NSProcessInfoThermalStateSerious || thermalState == NSProcessInfoThermalStateCritical) {
					if (@available(iOS 15.0, *)) {
						self->displayLink.preferredFrameRateRange = CAFrameRateRangeMake(30, 30, 30);
					} else {
						self->displayLink.preferredFramesPerSecond = 30;
					}
				} else {
					if (@available(iOS 15.0, *)) {
						self->displayLink.preferredFrameRateRange = CAFrameRateRangeMake(60, 120, 120);
					} else {
						self->displayLink.preferredFramesPerSecond = 60;
					}
				}
			}];
			
			success = true;
			dispatch_semaphore_signal(sem);
		}
	});
	
	// Wait for main thread to complete setup (with timeout)
	dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));

	this->setup = false;
	return success;
}

Dimension VideoDriver_iOS::GetScreenSize() const
{
	CGRect screenRect = [UIScreen mainScreen].bounds;
	CGFloat scale = [UIScreen mainScreen].scale;
	return { (uint)(screenRect.size.width * scale), (uint)(screenRect.size.height * scale) };
}

void VideoDriver_iOS::InputLoop()
{
    // On iOS, modifier key state is tracked per-event in UIKit
    // External keyboard support would require UIKeyCommand handlers
    // For now, fast forward can be triggered via toolbar or gestures
}

bool VideoDriver_iOS::LockVideoBuffer()
{
	if (this->buffer_locked) return false;
	this->buffer_locked = true;

	_screen.dst_ptr = this->GetVideoPointer();
	return true;
}

void VideoDriver_iOS::UnlockVideoBuffer()
{
	if (_screen.dst_ptr != nullptr) {
		this->ReleaseVideoPointer();
		_screen.dst_ptr = nullptr;
	}
	this->buffer_locked = false;
}

bool VideoDriver_iOS::PollEvent()
{
	// UIKit handles events
	return false;
}

void VideoDriver_iOS::GameSizeChanged()
{
	BlitterFactory::GetCurrentBlitter()->PostResize();
	::GameSizeChanged();
}

bool VideoDriver_iOS::AfterBlitterChange()
{
	this->AllocateBackingStore(true);
	return true;
}

// Touch Handling
// The key insight from window.cpp HandleMouseEvents():
// A click is detected when _left_button_down is true AND _left_button_clicked is false.
// HandleMouseEvents() then sets _left_button_clicked = true to mark it as processed.
// We should NOT set _left_button_clicked ourselves - that prevents the click from registering.

void VideoDriver_iOS::HandleTouchBegan(float x, float y, uintptr_t touch_id)
{
	// Ignore multi-touch for single-finger emulation
	if (this->active_touch_id != 0) return;
	this->active_touch_id = touch_id;

	float scale = this->metalView ? this->metalView.contentScaleFactor : 1.0f;

	// Track start position for drag detection
	this->touch_start_x = x;
	this->touch_start_y = y;
	this->touch_is_dragging = false;

	_cursor.pos.x = static_cast<int>(x * scale);
	_cursor.pos.y = static_cast<int>(y * scale);
	_left_button_down = true;
	// Don't set _left_button_clicked - HandleMouseEvents() detects the click
	// when _left_button_down is true and _left_button_clicked is false
	
	// Guard: only call HandleMouseEvents when game state is ready
	// (mirrors assertion in window.cpp:2967)
	if (HasModalProgress() || IsLocalCompany()) {
		HandleMouseEvents();
	}
}

void VideoDriver_iOS::HandleTouchMoved(float x, float y, uintptr_t touch_id)
{
	if (touch_id != this->active_touch_id) return;

	float scale = this->metalView ? this->metalView.contentScaleFactor : 1.0f;
	
	if (!this->touch_is_dragging) {
		float dx = x - this->touch_start_x;
		float dy = y - this->touch_start_y;
		// Use squared distance to avoid sqrt
		if (dx * dx + dy * dy > DRAG_THRESHOLD * DRAG_THRESHOLD) {
			this->touch_is_dragging = true;
			
			// Cancel the click/hold since we're dragging
			_left_button_down = false;
			_left_button_clicked = false;
			// Note: HandleMouseEvents() will process this "Mouse Up" below
		}
	}

	if (this->touch_is_dragging) {
		// Calculate delta from previous processed position
		// _cursor.pos stores the previous position in pixels
		float prev_x_points = _cursor.pos.x / scale;
		float prev_y_points = _cursor.pos.y / scale;
		
		float dx = x - prev_x_points;
		float dy = y - prev_y_points;
		
		this->HandlePan(dx, dy);
	}

	_cursor.pos.x = static_cast<int>(x * scale);
	_cursor.pos.y = static_cast<int>(y * scale);
	
	if (HasModalProgress() || IsLocalCompany()) {
		HandleMouseEvents();
	}
}

void VideoDriver_iOS::HandleTouchEnded(float x, float y, uintptr_t touch_id)
{
	if (touch_id != this->active_touch_id) return;

	float scale = this->metalView ? this->metalView.contentScaleFactor : 1.0f;
	_cursor.pos.x = static_cast<int>(x * scale);
	_cursor.pos.y = static_cast<int>(y * scale);

	if (this->touch_is_dragging) {
		// Drag ended. The button was already released when drag started.
		// Just reset the drag state.
	} else {
		// This was a tap.
		// Release the button - this allows a new click to be registered next time
		_left_button_down = false;
		_left_button_clicked = false;
	}

	this->touch_is_dragging = false;
	this->active_touch_id = 0;
	
	if (HasModalProgress() || IsLocalCompany()) {
		HandleMouseEvents();
	}
}

void VideoDriver_iOS::HandleTap(float x, float y)
{
	// Tap gesture - simulate a complete mouse click (down + up)
	float scale = this->metalView ? this->metalView.contentScaleFactor : 1.0f;
	_cursor.pos.x = static_cast<int>(x * scale);
	_cursor.pos.y = static_cast<int>(y * scale);
	
	// Guard: only process when game state is ready
	if (!HasModalProgress() && !IsLocalCompany()) return;
	
	// Mouse down - HandleMouseEvents detects _left_button_down && !_left_button_clicked
	_left_button_down = true;
	_left_button_clicked = false;
	HandleMouseEvents();
	
	// Mouse up
	_left_button_down = false;
	_left_button_clicked = false;
	HandleMouseEvents();
}

void VideoDriver_iOS::HandleRightClick(float x, float y)
{
	// Right click uses _right_button_clicked differently - it's checked directly
	// and cleared in HandleMouseEvents, so we DO set it to true here.
	float scale = this->metalView ? this->metalView.contentScaleFactor : 1.0f;
	_cursor.pos.x = static_cast<int>(x * scale);
	_cursor.pos.y = static_cast<int>(y * scale);
	
	// Guard: only process when game state is ready
	if (!HasModalProgress() && !IsLocalCompany()) return;
	
	_right_button_down = true;
	_right_button_clicked = true;
	HandleMouseEvents();
	_right_button_down = false;
}

void VideoDriver_iOS::HandlePan(float dx, float dy)
{
    float scale = this->metalView ? this->metalView.contentScaleFactor : 1.0f;
    _cursor.h_wheel -= dx * scale;
    _cursor.v_wheel -= dy * scale;
    _cursor.wheel_moved = true;
}

void VideoDriver_iOS::HandleZoomIn()
{
    _cursor.wheel--;
    if (HasModalProgress() || IsLocalCompany()) {
        HandleMouseEvents();
    }
}

void VideoDriver_iOS::HandleZoomOut()
{
    _cursor.wheel++;
    if (HasModalProgress() || IsLocalCompany()) {
        HandleMouseEvents();
    }
}

void VideoDriver_iOS::SetSafeAreaInsets(float top, float bottom, float left, float right)
{
	float scale = this->metalView ? this->metalView.contentScaleFactor : 1.0f;
	this->safe_area = {
		(int)(left * scale),
		(int)(top * scale),
		(int)(right * scale),
		(int)(bottom * scale)
	};
	
	NSLog(@"VideoDriver_iOS::SetSafeAreaInsets: %.1f, %.1f, %.1f, %.1f (scaled: %d, %d, %d, %d)", 
		  top, bottom, left, right, 
		  this->safe_area.left, this->safe_area.top, this->safe_area.right, this->safe_area.bottom);
}

// --------------------------------------------------------------------------------
// VideoDriver_iOSMetal Implementation
// --------------------------------------------------------------------------------

static FVideoDriver_iOSMetal iFVideoDriver_iOSMetal;

VideoDriver_iOSMetal::VideoDriver_iOSMetal()
{
	this->window_width  = 0;
	this->window_height = 0;
	this->window_pitch  = 0;
	this->buffer_depth  = 0;
	this->window_buffer = nullptr;
	this->pixel_buffer  = nullptr;
}

std::optional<std::string_view> VideoDriver_iOSMetal::Start(const StringList &param)
{
	NSLog(@"VideoDriver_iOSMetal::Start called");
	auto err = this->Initialize();
	if (err) {
		NSLog(@"VideoDriver_iOSMetal::Start - Initialize failed: %s", err->data());
		return err;
	}
	NSLog(@"VideoDriver_iOSMetal::Start - Initialize succeeded");

	NSLog(@"VideoDriver_iOSMetal::Start - calling MakeWindow with %dx%d", _cur_resolution.width, _cur_resolution.height);
	if (!this->MakeWindow(_cur_resolution.width, _cur_resolution.height)) {
		NSLog(@"VideoDriver_iOSMetal::Start - MakeWindow failed!");
		Stop();
		return "Could not create window";
	}
	NSLog(@"VideoDriver_iOSMetal::Start - MakeWindow succeeded");

	NSLog(@"VideoDriver_iOSMetal::Start - calling AllocateBackingStore");
	this->AllocateBackingStore(true);
	NSLog(@"VideoDriver_iOSMetal::Start - calling GameSizeChanged");
	this->GameSizeChanged();

	this->is_game_threaded = !GetDriverParamBool(param, "no_threads");
	NSLog(@"VideoDriver_iOSMetal::Start completed successfully, is_game_threaded=%d", this->is_game_threaded);

	return std::nullopt;
}

void VideoDriver_iOSMetal::Stop()
{
	this->VideoDriver_iOS::Stop();
	this->window_buffer.reset();
	this->pixel_buffer.reset();
	this->anim_buffer.reset();
}

void VideoDriver_iOSMetal::AllocateBackingStore(bool force)
{
	NSLog(@"VideoDriver_iOSMetal::AllocateBackingStore called, force=%d, metalView=%p, setup=%d",
		  force, this->metalView, this->setup);
	
	if (this->metalView == nil || this->setup) {
		NSLog(@"VideoDriver_iOSMetal::AllocateBackingStore - returning early!");
		return;
	}

	this->UpdatePalette(0, 256);

	CGSize size = this->metalView.drawableSize;
	this->window_width = (int)size.width;
	this->window_height = (int)size.height;
	this->window_pitch = Align(this->window_width, 16 / sizeof(uint32_t));
	this->buffer_depth = BlitterFactory::GetCurrentBlitter()->GetScreenDepth();

	NSLog(@"VideoDriver_iOSMetal::AllocateBackingStore - size=%dx%d, pitch=%d, depth=%d",
		  this->window_width, this->window_height, this->window_pitch, this->buffer_depth);

	size_t buffer_size = (size_t)this->window_pitch * this->window_height;
	this->window_buffer = std::make_unique<uint32_t[]>(buffer_size);
	this->anim_buffer = std::make_unique<uint8_t[]>(buffer_size);
	
	NSLog(@"VideoDriver_iOSMetal::AllocateBackingStore - buffers allocated: window_buffer=%p, anim_buffer=%p, size=%zu",
		  this->window_buffer.get(), this->anim_buffer.get(), buffer_size);

	if (this->buffer_depth == 8) {
		this->pixel_buffer = std::make_unique<uint8_t[]>(this->window_width * this->window_height);
	} else {
		this->pixel_buffer.reset();
	}

	_screen.width   = this->window_width;
	_screen.height  = this->window_height;
	_screen.pitch   = this->buffer_depth == 8 ? this->window_width : this->window_pitch;
	_screen.dst_ptr = this->GetVideoPointer();
	
	NSLog(@"VideoDriver_iOSMetal::AllocateBackingStore - _screen: %dx%d, pitch=%d, dst_ptr=%p",
		  _screen.width, _screen.height, _screen.pitch, _screen.dst_ptr);

	this->MakeDirty(0, 0, _screen.width, _screen.height);
	this->GameSizeChanged();
	
	NSLog(@"VideoDriver_iOSMetal::AllocateBackingStore - completed");
}

void VideoDriver_iOSMetal::Paint()
{
	static int paintCount = 0;
	paintCount++;
	if (paintCount <= 10 || paintCount % 300 == 0) {
		NSLog(@"VideoDriver_iOSMetal::Paint called, count=%d, metalView=%p, dirty_rect=(%d,%d,%d,%d)",
			  paintCount, this->metalView, 
			  this->dirty_rect.left, this->dirty_rect.top, 
			  this->dirty_rect.right, this->dirty_rect.bottom);
	}
	if (this->metalView) {
		[this->metalView draw];
	}
}

void VideoDriver_iOSMetal::CheckPaletteAnim()
{
	if (this->buffer_depth != 8) return;
    this->MakeDirty(0, 0, this->window_width, this->window_height);
}

void VideoDriver_iOSMetal::BlitIndexedToView32(int left, int top, int right, int bottom)
{
	const uint32_t *pal   = this->palette;
	const uint8_t  *src   = this->pixel_buffer.get();
	uint32_t       *dst   = this->window_buffer.get();
	uint          width = this->window_width;
	uint          pitch = this->window_pitch;

	for (int y = top; y < bottom; y++) {
		for (int x = left; x < right; x++) {
			dst[y * pitch + x] = pal[src[y * width + x]];
		}
	}
}

void VideoDriver_iOSMetal::UpdatePalette(uint first_colour, uint num_colours)
{
	if (this->buffer_depth != 8) return;
    
    for (uint i = 0; i < num_colours; i++) {
        uint c = first_colour + i;
        const Colour &col = _cur_palette.palette[c];
        // BGRA format: Alpha | Red | Green | Blue (Little Endian -> B G R A)
        // Metal BGRA8Unorm means 0th byte is Blue.
        // uint32 = 0xAARRGGBB.
        // Byte 0 (LSB) = BB. Byte 1 = GG. Byte 2 = RR. Byte 3 = AA.
        // So we construct 0xAARRGGBB.
        this->palette[c] = (255U << 24) | (col.r << 16) | (col.g << 8) | col.b;
    }
    
    this->MakeDirty(0, 0, this->window_width, this->window_height);
}


// Note: AppDelegate is defined in ios_main.mm (OTTDAppDelegate/OTTDSceneDelegate)
// The video driver integrates with the existing app lifecycle via SetupWithExistingWindow()

#endif /* TARGET_OS_IOS */
