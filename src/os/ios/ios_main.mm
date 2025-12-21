/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <https://www.gnu.org/licenses/old-licenses/gpl-2.0>.
 */

/** @file ios_main.mm Main entry for iOS. */

#include "../../stdafx.h"
#include "../../openttd.h"
#include "../../crashlog.h"
#include "../../core/random_func.hpp"
#include "../../string_func.h"
#include "ios.h"
#include "../../safeguards.h"

#import <UIKit/UIKit.h>

extern int openttd_main(const std::vector<std::string_view> &params);

static std::string _ios_documents_path;
static std::string _ios_bundle_path;

std::string GetIOSDocumentsPath()
{
	return _ios_documents_path;
}

std::string GetIOSBundlePath()
{
	return _ios_bundle_path;
}

void ShowIOSDialog(std::string_view title, std::string_view message, std::string_view button_label)
{
	dispatch_async(dispatch_get_main_queue(), ^{
		NSString *nsTitle = [NSString stringWithUTF8String:std::string(title).c_str()];
		NSString *nsMessage = [NSString stringWithUTF8String:std::string(message).c_str()];
		NSString *nsButton = [NSString stringWithUTF8String:std::string(button_label).c_str()];

		UIAlertController *alert = [UIAlertController alertControllerWithTitle:nsTitle message:nsMessage preferredStyle:UIAlertControllerStyleAlert];
		[alert addAction:[UIAlertAction actionWithTitle:nsButton style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
			if ([nsButton isEqualToString:@"Quit"]) {
				exit(0);
			}
		}]];

		UIViewController *rootVC = [[UIApplication sharedApplication] keyWindow].rootViewController;
		while (rootVC.presentedViewController) {
			rootVC = rootVC.presentedViewController;
		}
		[rootVC presentViewController:alert animated:YES completion:nil];
	});
}

void ShowMacDialog(std::string_view title, std::string_view message, std::string_view button_label)
{
	ShowIOSDialog(title, message, button_label);
}

void GetMacOSVersion(int *return_major, int *return_minor, int *return_bugfix)
{
	NSOperatingSystemVersion version = [[NSProcessInfo processInfo] operatingSystemVersion];
	if (return_major) *return_major = (int)version.majorVersion;
	if (return_minor) *return_minor = (int)version.minorVersion;
	if (return_bugfix) *return_bugfix = (int)version.patchVersion;
}

void MacOSSetThreadName(const std::string &name)
{
	[[NSThread currentThread] setName:[NSString stringWithUTF8String:name.c_str()]];
}

uint64_t MacOSGetPhysicalMemory()
{
	return [NSProcessInfo processInfo].physicalMemory;
}

void CocoaSetupAutoreleasePool()
{
	// No-op on iOS ARC/modern runtime usually, or handled by main's autoreleasepool
}

void CocoaReleaseAutoreleasePool()
{
	// No-op
}

@interface OTTDAppDelegate : UIResponder <UIApplicationDelegate>
@property (strong, nonatomic) UIWindow *window;
@end

@implementation OTTDAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
	if ([paths count] > 0) {
		_ios_documents_path = [[paths firstObject] UTF8String];
	}
	_ios_bundle_path = [[[NSBundle mainBundle] bundlePath] UTF8String];

	// Start OpenTTD in a background thread
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		std::vector<std::string_view> params;
		params.push_back("openttd");

		CrashLog::InitialiseCrashLog();
		SetRandomSeed(time(nullptr));

		openttd_main(params);
	});

	return YES;
}

@end

int main(int argc, char * argv[]) {
	@autoreleasepool {
		return UIApplicationMain(argc, argv, nil, NSStringFromClass([OTTDAppDelegate class]));
	}
}
