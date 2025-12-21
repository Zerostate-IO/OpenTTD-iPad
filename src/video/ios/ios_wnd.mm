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
    if (driver) {
        driver->TickWrapper();
    }
}

- (void)loadView
{
	// Create Metal view
	self.view = [ [ OTTD_MetalView alloc ] initWithFrame:UIScreen.mainScreen.bounds device:MTLCreateSystemDefaultDevice() driver:driver ];
	
	// Set the driver's Metal View pointer if needed or available
	if (driver) {
		driver->metalView = (OTTD_MetalView *)self.view;
	}
}

- (void)viewDidLoad
{
	[ super viewDidLoad ];
	
	// Disable system gestures if needed
	self.view.multipleTouchEnabled = YES;
}

// Pass touch events to driver
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	if (!driver) return;
	for (UITouch *touch in touches) {
		CGPoint loc = [ touch locationInView:self.view ];
		driver->HandleTouchBegan(loc.x, loc.y, (long)touch);
	}
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	if (!driver) return;
	for (UITouch *touch in touches) {
		CGPoint loc = [ touch locationInView:self.view ];
		driver->HandleTouchMoved(loc.x, loc.y, (long)touch);
	}
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event
{
	if (!driver) return;
	for (UITouch *touch in touches) {
		CGPoint loc = [ touch locationInView:self.view ];
		driver->HandleTouchEnded(loc.x, loc.y, (long)touch);
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

@interface OTTD_MetalView () <MTKViewDelegate>
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLTexture> gameTexture;
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

- (void)drawInMTKView:(MTKView *)view {
    if (!driver) return;
    
    void *buffer = driver->GetDisplayBuffer();
    if (!buffer) return;

    // Metal textures must be at least 1x1
    CGSize drawableSize = view.drawableSize;
    NSUInteger width = (NSUInteger)MAX(drawableSize.width, 1);
    NSUInteger height = (NSUInteger)MAX(drawableSize.height, 1);

    if (!_gameTexture || _gameTexture.width != width || _gameTexture.height != height) {
        MTLTextureDescriptor *textureDesc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                             width:width
                                                                                            height:height
                                                                                         mipmapped:NO];
        _gameTexture = [view.device newTextureWithDescriptor:textureDesc];
    }

    // Get the pitch from the driver (already aligned)
    NSUInteger bytesPerRow = driver->GetBufferPitch();
    
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
