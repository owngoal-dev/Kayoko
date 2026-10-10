# Simulator Builds

Use Xcode, an iOS 15 or later simulator, the standard Theos installation at `~/theos`, and Simject with
`CydiaSubstrate.framework`, `AltList.framework`, and PreferenceLoader installed in
`/opt/simject` (the same setup as SingleMute, SingleVPN, and Touch-Viz).

Run these commands from the repository root:

```sh
source devkit/simulator.sh
make
# Optional: boot a device listed by xcrun simctl list devices available.
devkit/sim-launch.sh <device_id>
make sim-install
```

`make` builds arm64 and x86_64 simulator artifacts in `.theos/obj/iphone_simulator`
(with Theos's configuration suffix, such as `debug`). `make sim-install` installs
both tweaks, the preferences bundle, and the updater in `/opt/simject`, prepares
the database and search index on the booted simulator, then runs `resim` and
restarts SpringBoard with `launchctl` to exit database maintenance mode.
Installation requires one booted simulator and `sudo`, and restarts its SpringBoard.

Simulator builds bypass purchase authorization and do not read or write purchase
credentials. History, images, tags, preferences, imported data, and thumbnail
caches use the running simulator's shared data directory instead of `/var/mobile`.
The updater preserves the host user's ownership. Device builds retain their
existing authorization and path behavior; source `devkit/rootless.sh`,
`devkit/roothide.sh`, or `devkit/env.sh` to switch back.
