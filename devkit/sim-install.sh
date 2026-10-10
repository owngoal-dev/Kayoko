#!/bin/sh
set -eu

if [ "${THEOS_DEVICE_SIMULATOR:-}" != 1 ]; then
  echo "Source devkit/simulator.sh before running make sim-install." >&2
  exit 1
fi

cd "$(dirname "$0")/.."
: "${THEOS_OBJ_DIR:?Run make sim-install to build and install the simulator artifacts.}"

for artifact in KayokoCore.dylib KayokoHelper.dylib KayokoPreferences.bundle kayoko_updater; do
  if [ ! -e "$THEOS_OBJ_DIR/$artifact" ]; then
    echo "Missing simulator build artifact: $THEOS_OBJ_DIR/$artifact" >&2
    exit 1
  fi
done

substrate_path=/opt/simject/CydiaSubstrate.framework/CydiaSubstrate
substrate_install_name=$(xcrun otool -D "$substrate_path" | sed -n '2p')
: "${substrate_install_name:?Unable to read the simulator Substrate install name.}"

sudo mkdir -p /opt/simject/PreferenceBundles /opt/simject/PreferenceLoader/Preferences
for component in Core Helper; do
  name="Kayoko$component"
  sudo install -m 755 "$THEOS_OBJ_DIR/$name.dylib" "/opt/simject/$name.dylib"
  sudo xcrun install_name_tool -change "$substrate_install_name" "$substrate_path" "/opt/simject/$name.dylib"
  sudo codesign -f -s - "/opt/simject/$name.dylib"
  sudo install -m 644 "Tweak/$component/$name.plist" "/opt/simject/$name.plist"
done

sudo rm -rf /opt/simject/PreferenceBundles/KayokoPreferences.bundle
sudo cp -R "$THEOS_OBJ_DIR/KayokoPreferences.bundle" /opt/simject/PreferenceBundles/
sudo codesign -f -s - /opt/simject/PreferenceBundles/KayokoPreferences.bundle
sudo cp -R Preferences/layout/Library/PreferenceLoader/Preferences/KayokoPreferences /opt/simject/PreferenceLoader/Preferences/
sudo install -m 755 "$THEOS_OBJ_DIR/kayoko_updater" /opt/simject/kayoko_updater
sudo codesign -f -s - /opt/simject/kayoko_updater

xcrun simctl spawn booted /opt/simject/kayoko_updater postinst
resim
# resim's graceful stop can leave SpringBoard in the updater's maintenance mode.
xcrun simctl spawn booted launchctl kickstart -k user/foreground/com.apple.SpringBoard
