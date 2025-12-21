# This file is part of OpenTTD.
# OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.

# iOS Platform Abstraction Layer
# Provides iOS-specific implementations for fonts, crash logging, strings, and app lifecycle

add_files(
    ios.h
    ios_stdafx.h
    font_ios.h
    ios_main.mm
    font_ios.mm
    crashlog_ios.mm
    string_ios.mm
    CONDITION IOS_BUILD
)

# iOS main entry point - linked directly to the executable
if(IOS_BUILD)
    target_sources(openttd PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/ios_main.mm)
endif()
