#!/usr/bin/env bash

# SPDX-FileCopyrightText: 2019-Present Christian Kußowski
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later

git apply ./scripts/enable-android-google-services.patch
KITE_ORIG_GROUP="im.fluffychat"
KITE_ORIG_TEAM="4NXF6Z997G"
#KITE_NEW_GROUP="app.kite"
#KITE_NEW_TEAM="ABCDE12345"

# In some cases (ie: running beta XCode releases) some pods haven't updated their minimum version
# but XCode will reject the package for using too old of a minimum version. 
# This will fix that, but. Well. Use at your own risk.
# export I_PROMISE_IM_REALLY_SMART=1

# If you want to automatically install the app
# export KITE_INSTALL_IPA=1

### Rotate IDs ###
[ -n "${KITE_NEW_GROUP}" ] && {
	# App group IDs
	sed -i "" "s/group.${KITE_ORIG_GROUP}.app/group.${KITE_NEW_GROUP}.app/g" "macos/Runner/Runner.entitlements"
	sed -i "" "s/group.${KITE_ORIG_GROUP}.app/group.${KITE_NEW_GROUP}.app/g" "macos/Runner.xcodeproj/project.pbxproj"
	# Bundle identifiers
	sed -i "" "s/${KITE_ORIG_GROUP}.app/${KITE_NEW_GROUP}.app/g" "macos/Runner.xcodeproj/project.pbxproj"
}

[ -n "${KITE_NEW_TEAM}" ] && {
	# Code signing team
	sed -i "" "s/${KITE_ORIG_TEAM}/${KITE_NEW_TEAM}/g" "macos/Runner.xcodeproj/project.pbxproj"
}

### Make release build ###
flutter build macos --release

echo "Build build/macos/Build/Products/Release/Kite.app"
