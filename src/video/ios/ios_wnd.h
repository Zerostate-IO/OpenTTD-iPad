/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <https://www.gnu.org/licenses/old-licenses/gpl-2.0>.
 */

/** @file ios_wnd.h OS interface for the iOS video driver. */

#ifndef IOS_WND_H
#define IOS_WND_H

#ifdef __APPLE__
#include <TargetConditionals.h>
#endif

#if TARGET_OS_IOS

#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>

class VideoDriver_iOS;

@interface OTTD_iOSViewController : UIViewController
- (instancetype)initWithDriver:(VideoDriver_iOS *)drv;
@end

@interface OTTD_MetalView : MTKView
- (instancetype)initWithFrame:(CGRect)frameRect device:(id<MTLDevice>)device driver:(VideoDriver_iOS *)drv;
@end

bool iOSSetupApplication();
void iOSExitApplication();

#endif /* TARGET_OS_IOS */

#endif /* IOS_WND_H */
