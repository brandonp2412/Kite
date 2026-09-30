# Repository agent instructions

## Android device installs

Never use `flutter install` to install Kite on a physical Android device. Flutter's install command uninstalls the existing package before reinstalling it, which wipes app data.

Use `scripts/install-android-preserve-data.sh [adb-serial]` instead. It builds the release APK and installs it with `adb install -t -r`, preserving app data. If Android rejects the update because of a signing-key mismatch or version downgrade, stop and report the error; do not uninstall the existing app as a fallback.
