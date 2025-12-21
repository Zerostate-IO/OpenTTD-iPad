/*
 * This file is part of OpenTTD.
 * OpenTTD is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, version 2.
 * OpenTTD is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
 * See the GNU General Public License for more details. You should have received a copy of the GNU General Public License along with OpenTTD. If not, see <https://www.gnu.org/licenses/old-licenses/gpl-2.0>.
 */

/** @file ios.h Functions related to iOS support. */

#ifndef IOS_H
#define IOS_H

#include <string>
#include <string_view>
#include <CoreFoundation/CoreFoundation.h>

// Include shared macOS declarations to avoid duplication and conflicts
#include "../macosx/macos.h"

/** Helper function displaying a message using UIAlertController. */
void ShowIOSDialog(std::string_view title, std::string_view message, std::string_view button_label);

/** Get the path to the Documents directory. */
std::string GetIOSDocumentsPath();

/** Get the path to the App Bundle directory. */
std::string GetIOSBundlePath();

#endif /* IOS_H */
