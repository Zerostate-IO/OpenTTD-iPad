/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <https://www.gnu.org/licenses/old-licenses/gpl-2.0>.
 */

/** @file ios_wnd.mm Code related to OS interface for the iOS video driver. */

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

#if TARGET_OS_IOS

#include "../../stdafx.h"
#include "../../openttd.h"
#include "../../debug.h"
#include "ios_v.h"
#include "ios_wnd.h"

@implementation OTTD_iOSViewController {
	VideoDriver_iOS *driver;
}

- (instancetype)initWithDriver:(VideoDriver_iOS *)drv
{
	self = [ super initWithNibName:nil bundle:nil ];
	if (self) {
		driver = drv;
	}
	return self;
}

- (void)displayLinkFired:(CADisplayLink *)link {
    // Display link fires on the main thread at vsync rate.
    // This is the correct place to drive Tick() for iOS - ensures all
    // drawing happens on the main thread where Metal/UIKit expects it.
    // The game thread handles game logic separately via StartGameThread().
    if (driver && driver->IsReadyForTick()) {
        driver->TickWrapper();
    }
}

- (void)loadView
{
	NSLog(@"OTTD_iOSViewController loadView called");
	// Create Metal view
	id<MTLDevice> device = MTLCreateSystemDefaultDevice();
	NSLog(@"OTTD_iOSViewController: Metal device: %@", device);
	if (!device) {
		NSLog(@"OTTD_iOSViewController: ERROR - No Metal device available!");
	}
	CGRect bounds = UIScreen.mainScreen.bounds;
	NSLog(@"OTTD_iOSViewController: Screen bounds: %@", NSStringFromCGRect(bounds));
	self.view = [ [ OTTD_MetalView alloc ] initWithFrame:bounds device:device driver:driver ];
	NSLog(@"OTTD_iOSViewController: Metal view created: %@", self.view);
	
	// Set the driver's Metal View pointer if needed or available
	if (driver) {
		driver->metalView = (OTTD_MetalView *)self.view;
		NSLog(@"OTTD_iOSViewController: Set driver->metalView");
	}
}

- (void)viewDidLoad
{
	[ super viewDidLoad ];
	
	// Disable system gestures if needed
	self.view.multipleTouchEnabled = YES;
}

// Pass touch events to driver (for both finger and Apple Pencil)
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	NSLog(@"touchesBegan: count=%lu", (unsigned long)touches.count);
	if (!driver) return;
	for (UITouch *touch in touches) {
		CGPoint loc = [ touch locationInView:self.view ];
		NSLog(@"touchesBegan: loc=(%.1f, %.1f), scale=%.1f", loc.x, loc.y, self.view.contentScaleFactor);
		driver->HandleTouchBegan(loc.x, loc.y, (uintptr_t)touch);
	}
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	if (!driver) return;
	for (UITouch *touch in touches) {
		CGPoint loc = [ touch locationInView:self.view ];
		driver->HandleTouchMoved(loc.x, loc.y, (uintptr_t)touch);
	}
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	NSLog(@"touchesEnded: count=%lu", (unsigned long)touches.count);
	if (!driver) return;
	for (UITouch *touch in touches) {
		CGPoint loc = [ touch locationInView:self.view ];
		NSLog(@"touchesEnded: loc=(%.1f, %.1f)", loc.x, loc.y);
		driver->HandleTouchEnded(loc.x, loc.y, (uintptr_t)touch);
	}
}

- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	[ self touchesEnded:touches withEvent:event ];
}

// Hide status bar
- (BOOL)prefersStatusBarHidden
{
	return YES;
}

// Auto-rotate support
- (BOOL)shouldAutorotate
{
	return YES;
}

@end


#import <Metal/Metal.h>

static const char* kMetalShaderSource = R"(
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                            constant float2 *positions [[buffer(0)]],
                            constant float2 *texCoords [[buffer(1)]]) {
    VertexOut out;
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    return out;
}

fragment float4 fragmentShader(VertexOut in [[stage_in]],
                             texture2d<float> texture [[texture(0)]]) {
    constexpr sampler s(mag_filter::nearest, min_filter::nearest);
    return texture.sample(s, in.texCoord);
}
)";

@interface OTTD_MetalView () <MTKViewDelegate, UIGestureRecognizerDelegate>
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLTexture> gameTexture;
@property (nonatomic, assign) float accumulatedPinchScale;
@end

@implementation OTTD_MetalView {
	VideoDriver_iOS *driver;
    id<MTLBuffer> vertexBuffer;
    id<MTLBuffer> texCoordBuffer;
}

- (instancetype)initWithFrame:(CGRect)frameRect device:(id<MTLDevice>)device driver:(VideoDriver_iOS *)drv
{
	self = [ super initWithFrame:frameRect device:device ];
	if (self) {
		driver = drv;
		
		self.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
		self.framebufferOnly = YES;
		self.delegate = self;
		self.paused = YES; 
        self.enableSetNeedsDisplay = NO;

        _commandQueue = [device newCommandQueue];

        [self setupPipeline:device];
        [self setupBuffers:device];
        [self setupGestureRecognizers];
	}
	return self;
}

- (void)setupPipeline:(id<MTLDevice>)device {
    NSError *error = nil;
    NSString *shaderSource = [NSString stringWithUTF8String:kMetalShaderSource];
    id<MTLLibrary> library = [device newLibraryWithSource:shaderSource options:nil error:&error];
    if (!library) {
        NSLog(@"Failed to create library: %@", error);
        return;
    }

    id<MTLFunction> vertexFunc = [library newFunctionWithName:@"vertexShader"];
    id<MTLFunction> fragmentFunc = [library newFunctionWithName:@"fragmentShader"];

    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.vertexFunction = vertexFunc;
    pipelineDescriptor.fragmentFunction = fragmentFunc;
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.colorPixelFormat;

    _pipelineState = [device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    if (!_pipelineState) {
        NSLog(@"Failed to create pipeline state: %@", error);
    }
}

- (void)setupBuffers:(id<MTLDevice>)device {
    static const float positions[] = {
        -1.0, -1.0,
         1.0, -1.0,
        -1.0,  1.0,
         1.0,  1.0,
    };
    static const float texCoords[] = {
        0.0, 1.0,
        1.0, 1.0,
        0.0, 0.0,
        1.0, 0.0,
    };

    vertexBuffer = [device newBufferWithBytes:positions length:sizeof(positions) options:MTLResourceStorageModeShared];
    texCoordBuffer = [device newBufferWithBytes:texCoords length:sizeof(texCoords) options:MTLResourceStorageModeShared];
}

- (void)setupGestureRecognizers {
    // NOTE: We do NOT use a single-tap gesture recognizer.
    // Single-finger taps/clicks are handled via touchesBegan/touchesEnded on the view controller.
    // This gives us the lowest latency and most reliable click detection.
    // Gesture recognizers are used only for multi-touch and complex gestures.

    // Two-finger tap (right-click)
    UITapGestureRecognizer *twoFingerTap = [[UITapGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleTwoFingerTap:)];
    twoFingerTap.numberOfTouchesRequired = 2;
    twoFingerTap.delegate = self;
    twoFingerTap.cancelsTouchesInView = NO;

    // Long press (right-click, 500ms)
    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = 0.5;
    longPress.allowableMovement = 15;
    longPress.delegate = self;
    longPress.cancelsTouchesInView = NO;

    // Pinch (zoom) - two finger gesture
    UIPinchGestureRecognizer *pinch = [[UIPinchGestureRecognizer alloc]
        initWithTarget:self action:@selector(handlePinch:)];
    pinch.delegate = self;
    pinch.cancelsTouchesInView = NO;

    // Two-finger pan for scrolling the viewport
    UIPanGestureRecognizer *twoFingerPan = [[UIPanGestureRecognizer alloc]
        initWithTarget:self action:@selector(handleTwoFingerPan:)];
    twoFingerPan.minimumNumberOfTouches = 2;
    twoFingerPan.maximumNumberOfTouches = 2;
    twoFingerPan.delegate = self;
    twoFingerPan.cancelsTouchesInView = NO;

    [self addGestureRecognizer:twoFingerTap];
    [self addGestureRecognizer:longPress];
    [self addGestureRecognizer:pinch];
    [self addGestureRecognizer:twoFingerPan];
}

- (void)handleTwoFingerTap:(UITapGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateEnded) {
        CGPoint loc = [gesture locationInView:self];
        NSLog(@"handleTwoFingerTap: location=(%.1f, %.1f)", loc.x, loc.y);
        if (driver) driver->HandleRightClick(loc.x, loc.y);
    }
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        // Haptic feedback
        UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
        [feedback impactOccurred];
        
        CGPoint loc = [gesture locationInView:self];
        NSLog(@"handleLongPress: location=(%.1f, %.1f)", loc.x, loc.y);
        if (driver) driver->HandleRightClick(loc.x, loc.y);
    }
}

- (void)handleTwoFingerPan:(UIPanGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint translation = [gesture translationInView:self];
        if (driver) driver->HandlePan(translation.x, translation.y);
        [gesture setTranslation:CGPointZero inView:self];
    }
}

- (void)handlePinch:(UIPinchGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        self.accumulatedPinchScale = 1.0f;
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        self.accumulatedPinchScale *= gesture.scale;
        gesture.scale = 1.0f;
        
        if (self.accumulatedPinchScale > 1.5f) {
            if (driver) driver->HandleZoomIn();
            self.accumulatedPinchScale = 1.0f;
        } else if (self.accumulatedPinchScale < 0.67f) {
            if (driver) driver->HandleZoomOut();
            self.accumulatedPinchScale = 1.0f;
        }
    }
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g1 shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)g2 {
    // Allow pan + pinch
    if (([g1 isKindOfClass:[UIPanGestureRecognizer class]] && [g2 isKindOfClass:[UIPinchGestureRecognizer class]]) ||
        ([g1 isKindOfClass:[UIPinchGestureRecognizer class]] && [g2 isKindOfClass:[UIPanGestureRecognizer class]])) {
        return YES;
    }
    return NO;
}

- (void)drawInMTKView:(MTKView *)view {
    static int drawCount = 0;
    drawCount++;
    
    if (!driver) {
        if (drawCount <= 5) NSLog(@"OTTD_MetalView drawInMTKView: no driver!");
        return;
    }
    
    void *buffer = driver->GetDisplayBuffer();
    if (!buffer) {
        if (drawCount <= 5) NSLog(@"OTTD_MetalView drawInMTKView: no buffer!");
        return;
    }

    // Metal textures must be at least 1x1
    CGSize drawableSize = view.drawableSize;
    NSUInteger width = (NSUInteger)MAX(drawableSize.width, 1);
    NSUInteger height = (NSUInteger)MAX(drawableSize.height, 1);

    if (drawCount <= 5 || drawCount % 300 == 0) {
        NSLog(@"OTTD_MetalView drawInMTKView: count=%d, size=%lux%lu, buffer=%p", 
              drawCount, (unsigned long)width, (unsigned long)height, buffer);
    }

    if (!_gameTexture || _gameTexture.width != width || _gameTexture.height != height) {
        NSLog(@"OTTD_MetalView drawInMTKView: creating texture %lux%lu", (unsigned long)width, (unsigned long)height);
        MTLTextureDescriptor *textureDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                             width:width
                                                                                            height:height
                                                                                         mipmapped:NO];
        _gameTexture = [view.device newTextureWithDescriptor:textureDesc];
    }

    // Get the pitch from the driver (already aligned)
    NSUInteger bytesPerRow = driver->GetBufferPitch() * sizeof(uint32_t);
    
    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
    
    // We assume the buffer size matches the view size because AllocateBackingStore uses view.drawableSize
    [_gameTexture replaceRegion:region mipmapLevel:0 withBytes:buffer bytesPerRow:bytesPerRow];

    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    MTLRenderPassDescriptor *passDescriptor = view.currentRenderPassDescriptor;

    if (passDescriptor) {
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:passDescriptor];
        [renderEncoder setRenderPipelineState:_pipelineState];
        [renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
        [renderEncoder setVertexBuffer:texCoordBuffer offset:0 atIndex:1];
        [renderEncoder setFragmentTexture:_gameTexture atIndex:0];
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [renderEncoder endEncoding];
        [commandBuffer presentDrawable:view.currentDrawable];
    } else {
        if (drawCount <= 5) NSLog(@"OTTD_MetalView drawInMTKView: no passDescriptor!");
    }
    
    [commandBuffer commit];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    if (driver) driver->GameSizeChanged();
}

@end


bool iOSSetupApplication()
{
	// Stub for iOS app setup
	return true;
}

void iOSExitApplication()
{
	// Stub for iOS app exit
}

#endif /* TARGET_OS_IOS */
