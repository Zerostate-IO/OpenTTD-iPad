# This file is part of OpenTTD.
# OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.

# iOS-specific CMake configuration
# Usage: cmake -DCMAKE_TOOLCHAIN_FILE=cmake/iOS.cmake ...
# Or:    cmake -DCMAKE_SYSTEM_NAME=iOS ...

# Set the system name to iOS
set(CMAKE_SYSTEM_NAME iOS)

# Target iPadOS 17.0+ (compatible with iPadOS 26.2)
# Note: CMake uses iOS SDK version numbers. iPadOS 26.2 uses iOS SDK 17+
set(CMAKE_OSX_DEPLOYMENT_TARGET "17.0" CACHE STRING "Minimum iOS version")

# IMPORTANT: Do NOT set CMAKE_OSX_ARCHITECTURES or CMAKE_OSX_SYSROOT here!
# Xcode needs to control these based on the selected destination (device vs simulator).
# - Device builds use arm64 with iphoneos SDK
# - Simulator builds use arm64 (Apple Silicon) or x86_64 (Intel) with iphonesimulator SDK
# Setting them here causes SDK mismatch errors when building for simulator.

# Mark this as an iOS build for conditional CMake logic
set(IOS_BUILD ON CACHE BOOL "Building for iOS/iPadOS")

# Disable features not available/applicable on iOS
set(OPTION_DEDICATED OFF CACHE BOOL "" FORCE)

# iOS doesn't have pkg-config in the traditional sense
set(PKG_CONFIG_EXECUTABLE "" CACHE STRING "" FORCE)

# Disable features that don't make sense on iOS
set(OPTION_INSTALL_FHS OFF CACHE BOOL "" FORCE)

message(STATUS "iOS Build Configuration:")
message(STATUS "  CMAKE_SYSTEM_NAME: ${CMAKE_SYSTEM_NAME}")
message(STATUS "  CMAKE_OSX_DEPLOYMENT_TARGET: ${CMAKE_OSX_DEPLOYMENT_TARGET}")
message(STATUS "  Note: Architecture and SDK controlled by Xcode destination")
