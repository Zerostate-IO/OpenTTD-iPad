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
	// Launch the iOS Run Loop
	// Note: In a real implementation, we might need to handle this differently
	// as UIApplicationMain blocks. OpenTTD expects to drive the loop.
	// For this skeleton, we assume UIApplicationMain will be called here.
	
	char *argv[] = { (char *)"openttd", nullptr };
	UIApplicationMain(0, argv, nil, @"OTTD_iOSAppDelegate");
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

	// On iOS, we normally let the AppDelegate create the window,
	// but here we might need to create the VC if we are early.
	// Assuming iOSSetupApplication does the heavy lifting or we do it here.
	
	this->viewController = [ [ OTTD_iOSViewController alloc ] initWithDriver:this ];
	
	// Access the view to trigger loadView
	UIView *v = this->viewController.view;
	if ([v isKindOfClass:[OTTD_MetalView class]]) {
		this->metalView = (OTTD_MetalView *)v;
	}

    // Setup DisplayLink
    this->displayLink = [CADisplayLink displayLinkWithTarget:this->viewController selector:@selector(displayLinkFired:)];
    
    // Initial thermal state check
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
    
    [this->displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    // Observer for thermal state
    [[NSNotificationCenter defaultCenter] addObserverForName:NSProcessInfoThermalStateDidChangeNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification * _Nonnull note) {
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
    }];

	this->setup = false;
	return true;
}

Dimension VideoDriver_iOS::GetScreenSize() const
{
	CGRect screenRect = [UIScreen mainScreen].bounds;
	CGFloat scale = [UIScreen mainScreen].scale;
	return { (uint)(screenRect.size.width * scale), (uint)(screenRect.size.height * scale) };
}

void VideoDriver_iOS::InputLoop()
{
	// Handle input processing if needed
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
	::GameSizeChanged();
}

bool VideoDriver_iOS::AfterBlitterChange()
{
	this->AllocateBackingStore(true);
	return true;
}

// Touch Handling Stubs
void VideoDriver_iOS::HandleTouchBegan(float x, float y, int touch_id)
{
	_cursor.pos.x = static_cast<int>(x);
	_cursor.pos.y = static_cast<int>(y);
	_left_button_down = true;
	_left_button_clicked = true;
}

void VideoDriver_iOS::HandleTouchMoved(float x, float y, int touch_id)
{
	_cursor.pos.x = static_cast<int>(x);
	_cursor.pos.y = static_cast<int>(y);
}

void VideoDriver_iOS::HandleTouchEnded(float x, float y, int touch_id)
{
	_left_button_down = false;
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
	auto err = this->Initialize();
	if (err) return err;

	if (!this->MakeWindow(_cur_resolution.width, _cur_resolution.height)) {
		Stop();
		return "Could not create window";
	}

	this->AllocateBackingStore(true);
	this->GameSizeChanged();

	this->is_game_threaded = !GetDriverParamBool(param, "no_threads");

	return std::nullopt;
}

void VideoDriver_iOSMetal::Stop()
{
	this->VideoDriver_iOS::Stop();
	this->window_buffer.reset();
	this->pixel_buffer.reset();
}

void VideoDriver_iOSMetal::AllocateBackingStore(bool force)
{
	if (this->metalView == nil || this->setup) return;

	this->UpdatePalette(0, 256);

	// Get size from Metal view
	CGSize size = this->metalView.drawableSize;
	this->window_width = (int)size.width;
	this->window_height = (int)size.height;
	this->window_pitch = Align(this->window_width, 16 / sizeof(uint32_t));
	this->buffer_depth = BlitterFactory::GetCurrentBlitter()->GetScreenDepth();

	// Allocate buffer
	this->window_buffer = std::make_unique<uint32_t[]>(this->window_pitch * this->window_height);

	if (this->buffer_depth == 8) {
		this->pixel_buffer = std::make_unique<uint8_t[]>(this->window_width * this->window_height);
	} else {
		this->pixel_buffer.reset();
	}

	_screen.width   = this->window_width;
	_screen.height  = this->window_height;
	_screen.pitch   = this->buffer_depth == 8 ? this->window_width : this->window_pitch;
	_screen.dst_ptr = this->GetVideoPointer();

	this->MakeDirty(0, 0, _screen.width, _screen.height);
	this->GameSizeChanged();
}

void VideoDriver_iOSMetal::Paint()
{
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
        const Colour &col = _cur_palette[c];
        // BGRA format: Alpha | Red | Green | Blue (Little Endian -> B G R A)
        // Metal BGRA8Unorm means 0th byte is Blue.
        // uint32 = 0xAARRGGBB.
        // Byte 0 (LSB) = BB. Byte 1 = GG. Byte 2 = RR. Byte 3 = AA.
        // So we construct 0xAARRGGBB.
        this->palette[c] = (255U << 24) | (col.r << 16) | (col.g << 8) | col.b;
    }
    
    this->MakeDirty(0, 0, this->window_width, this->window_height);
}


// AppDelegate needed for UIApplicationMain
@interface OTTD_iOSAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation OTTD_iOSAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	// If the VideoDriver created the Window, we might want to use it.
	// Or we create it here.
	
	VideoDriver_iOS *drv = (VideoDriver_iOS *)VideoDriver::GetInstance();
	if (drv && drv->viewController) {
		self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
		self.window.rootViewController = drv->viewController;
		[self.window makeKeyAndVisible];
		drv->window = self.window;
	}
	
	return YES;
}
@end

#endif /* TARGET_OS_IOS */
