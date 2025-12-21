# This file is part of OpenTTD.
# OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.

# iOS Video Driver - Metal-backed rendering with UIKit
# Only compiled when building for iOS (CMAKE_SYSTEM_NAME = iOS)

add_files(
    ios_v.h
    ios_v.mm
    ios_wnd.h
    ios_wnd.mm
    CONDITION IOS_BUILD
)
