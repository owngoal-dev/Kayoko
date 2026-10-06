# iOS system gesture type mappings

Kayoko blocks `Show Cover Sheet` and `Show ControlCenter` while fullscreen search is active. It blocks `Switcher Bottom Edge` while the preview or word selection view has a visible tag bar. SpringBoard assigns different IDs to these gestures across iOS releases, so each system major version selects its own mapping.

Sampling date: 2026-10-07. The mappings are used by `installSystemGestureHooks` in [KayokoSpringBoardHooks.m](../Tweak/Core/KayokoSpringBoardHooks.m).

## Gesture IDs used by Kayoko

| iOS major version | Sampled releases | Show Cover Sheet | Show ControlCenter | Switcher Bottom Edge |
| --- | --- | --- | --- | --- |
| 14 | 14.8 | `0x1` | `0x6` | `0x20` |
| 15 | 15.0 | `0x1` | `0x6` | `0x29` |
| 16 | 16.0, 16.7 | `0x1` | `0x6` | `0x2B` |
| 17 | 17.0, 17.4 | `0x1` | `0x6` | `0x2D` |
| 18 | 18.0, 18.3 | `0x1` | `0x6` | `0x2D` |
| 26 | 26.0, 26.0.1 | `0x1` | `0x38` | `0x27` |

The sampled minor releases keep these three policy IDs, although their complete type tables differ. The hook uses exactly one multitasking ID for the running system major version. A major version without a sampled mapping keeps SpringBoard's native policy.

## Why the former combined IDs were unsafe

The old `0x29`, `0x2B`, and `0x2D` checks were the bottom edge IDs for different releases. Matching all three in every release also matched other actions.

| Sample | `0x29` | `0x2B` | `0x2D` |
| --- | --- | --- | --- |
| 15.0 | Switcher Bottom Edge | Dismiss Alert Item | Dismiss Modal UI From Pointer |
| 16.0 | Dismiss Floating Application From Pointer | Switcher Bottom Edge | Dismiss Alert Item |
| 17.0 | Present Right Floating Application From Pointer | Dismiss Floating Application From Pointer | Switcher Bottom Edge |
| 18.0 | Unknown | Present Left Floating Application From Pointer | Switcher Bottom Edge |
| 26.0 | Dismiss Alert Item | Dismiss Modal UI From Pointer | Dismiss Alert Item From Pointer |

## Sample provenance

Sample root: `/Users/82flex/Codelab/dyld`.

Each path below identifies the main cache. Its sibling subcaches and symbols belong to the same sample. Addresses are unslid addresses of `_SBSystemGestureTypeDebugName` in `/System/Library/PrivateFrameworks/SpringBoard.framework/SpringBoard`.

| iOS sample | Main cache path relative to the sample root | Main cache UUID | Name function address |
| --- | --- | --- | --- |
| 14.8 | `iOS_14.8__local__arm64/dyld_shared_cache_arm64` | `2BEC66E4-84D4-3C6E-919C-830A676FA8AE` | `0x00000001a4561934` |
| 15.0 | `iOS_15.0__local__arm64e/dyld_shared_cache_arm64e` | `62C73193-8456-3D38-B29B-16E3F352F829` | `0x00000001ad329738` |
| 16.0 | `iOS_16.0__20A362__iPhone15,2/dyld_shared_cache_arm64e` | `9D337A95-544D-32FF-8A6F-08C745415564` | `0x00000001c6c35da0` |
| 16.7 | `iOS_16.7__local__arm64/dyld_shared_cache_arm64` | `6CC69D47-36F1-32A1-AE28-AFED14BD6E23` | `0x00000001c5ca61f0` |
| 17.0 | `iOS_17.0__local__arm64e/dyld_shared_cache_arm64e` | `5E8777F5-AABC-3DEE-9B07-0BCF718A8AB4` | `0x00000001d2a90918` |
| 17.4 | `iOS_17.4__21E219__iPhone15,2/dyld_shared_cache_arm64e` | `3A950891-1D82-3B33-AA78-C4123220DEBE` | `0x00000001d5573380` |
| 18.0 | `iOS_18.0__22A3354__iPhone15,2/dyld_shared_cache_arm64e` | `1CB4CA5F-879F-3596-9756-0D26CD021BEF` | `0x00000001d76d9830` |
| 18.3 | `iOS_18.3__local__arm64/dyld_shared_cache_arm64` | `06DBF50A-8F14-34E8-9262-6B62EFA2AFC8` | `0x00000001d1faeb74` |
| 26.0 | `iOS_26.0__23A341__iPhone12,8/23A341__iPhone12,8/dyld_shared_cache_arm64e` | `1A7A60D2-008E-34C5-A14C-8E9B650C89AA` | `0x000000021d5b959c` |
| 26.0.1 | `iOS_26.0.1__23A355__iPhone12,8/23A355__iPhone12,8/dyld_shared_cache_arm64e` | `BE531402-BEC8-386E-8364-2452872166C1` | `0x000000021d5b559c` |

## Runtime registration on Z26

On Z26 running iOS 26.0.1, `SBMainDisplaySystemGestureManager.sharedInstance` exposes the following entries in `_typeToGesture`. These entries associate the sampled policy IDs with the actual recognizers.

| Type | Recognizer class | Recognizer name |
| --- | --- | --- |
| `0x1` | `SBCoverSheetPresentationGestureRecognizer` | `CoverSheetGrabberTongue-edgePullGestureRecognizer-1` |
| `0x27` | `SBFluidSwitcherScreenEdgePanGestureRecognizer` | `DeckGrabberTongue-edgePullGestureRecognizer-4` |
| `0x38` | `SBScreenEdgePanGestureRecognizer` | `ControlCenterGrabberTongue-edgePullGestureRecognizer-1` |

`SBFluidSwitcherGestureManager.homeGestureBottomEdgeRecognizer` also resolves to type `0x27` through `typeOfSystemGesture:`. Other registered gestures such as `0x2A` belong to different actions and are not added to Kayoko's policy.

## Repeating the lookup

Tools: `ipsw` 3.1.713 and Xcode `otool`. Replace the sample path when examining another release.

```sh
KAYOKO_DSC='/Users/82flex/Codelab/dyld/iOS_26.0__23A341__iPhone12,8/23A341__iPhone12,8/dyld_shared_cache_arm64e'
KAYOKO_SB_IMAGE='/System/Library/PrivateFrameworks/SpringBoard.framework/SpringBoard'

# List image symbols and strings without constructing an index of the entire cache.
ipsw dyld macho "$KAYOKO_DSC" "$KAYOKO_SB_IMAGE" --symbols --strings --no-color

# Extract into a scratch directory and inspect the type-name function.
ipsw dyld extract "$KAYOKO_DSC" "$KAYOKO_SB_IMAGE" --slide --output /tmp/kayoko-system-gestures --no-color
xcrun otool -tvV -p _SBSystemGestureTypeDebugName /tmp/kayoko-system-gestures/SpringBoard

# Read the first bytes at the sampled name function entry.
ipsw dyld dump "$KAYOKO_DSC" 0x000000021d5b959c --bytes --size 32
```

A type is the input integer of `SBSystemGestureTypeDebugName`. Follow its switch table entry to the selected `__cfstring` constant; string order alone does not establish the ID. The function uses byte or signed word jump tables depending on the release. The full image path avoids ambiguity with the accessibility bundle also named `SpringBoard`.

The full tables below preserve the static names verbatim. `Unknown` means that the corresponding switch entry goes to the dynamic fallback branch rather than a static name. It does not mean the ID is unregistered: Z26 registers type `0x6` as `indirectPresentCoverSheetGestureRecognizer` even though it has no static name in this function. `None` is a literal static name.

Before adding a new major version, compare the intended names against that sample's table and their registered recognizers. Add only the matching policy IDs to the version selection.

## Full static type tables

### iOS 14.8

| Type | Static debug name |
| --- | --- |
| `0x0` | None |
| `0x1` | Show Cover Sheet |
| `0x2` | Dismiss Cover Sheet |
| `0x3` | Dismiss Cover Sheet More |
| `0x4` | Dismiss Secure App |
| `0x5` | Dismiss Long Look |
| `0x6` | Show ControlCenter |
| `0x7` | Show Control Center from Status Bar |
| `0x8` | Dismiss Control Center |
| `0x9` | Unknown |
| `0xA` | Show Control Center from Status Bar from Pointer |
| `0xB` | Dismiss Cover Sheet from Pointer |
| `0xC` | Dismiss Cover Sheet Scrunch |
| `0xD` | Dismiss Secure App from Pointer |
| `0xE` | Dismiss Secure App Scrunch |
| `0xF` | Dismiss Control Center From Pointer |
| `0x10` | Dismiss Control Center Scrunch |
| `0x11` | Scrunch |
| `0x12` | Floating Application Scrunch |
| `0x13` | Scene Resize |
| `0x14` | Unpin Side Application |
| `0x15` | Present Floating Application |
| `0x16` | Move Floating Application |
| `0x17` | Pin Floating Application |
| `0x18` | Floating Application Bottom Edge |
| `0x19` | Dismiss Dock |
| `0x1A` | Unknown |
| `0x1B` | Unknown |
| `0x1C` | Unknown |
| `0x1D` | Present Floating Application From Pointer |
| `0x1E` | Dismiss Floating Application From Pointer |
| `0x1F` | Switcher Force Press |
| `0x20` | Switcher Bottom Edge |
| `0x21` | Dismiss Modal UI |
| `0x22` | Dismiss Alert Item |
| `0x23` | Click and Drag Home Gesture |
| `0x24` | Dismiss Modal UI From Pointer |
| `0x25` | Dismiss Modal UI Scrunch |
| `0x26` | Dismiss Alert Item From Pointer |
| `0x27` | Dismiss Alert Item Scrunch |
| `0x28` | Unknown |
| `0x29` | Unknown |
| `0x2A` | Unknown |
| `0x2B` | Unknown |
| `0x2C` | Unknown |
| `0x2D` | Unknown |
| `0x2E` | CarPlay Banner Dismiss |
| `0x2F` | Unknown |
| `0x30` | Unknown |
| `0x31` | Unknown |
| `0x32` | Unknown |
| `0x33` | Unknown |
| `0x34` | Unknown |
| `0x35` | Unknown |
| `0x36` | Unknown |
| `0x37` | Unknown |
| `0x38` | Unknown |
| `0x39` | Unknown |
| `0x3A` | Unknown |
| `0x3B` | Unknown |
| `0x3C` | Unknown |
| `0x3D` | Unknown |
| `0x3E` | Unknown |
| `0x3F` | Unknown |
| `0x40` | Unknown |
| `0x41` | Unknown |
| `0x42` | Unknown |
| `0x43` | Unknown |
| `0x44` | Unknown |
| `0x45` | Unknown |
| `0x46` | Unknown |
| `0x47` | Unknown |
| `0x48` | Dismiss Camera UI DashBoard |
| `0x49` | Dimiss Modal UI DashBoard |
| `0x4A` | Dismiss Camera UI DashBoard From Pointer |
| `0x4B` | Dismiss Camera UI DashBoard Scrunch |
| `0x4C` | Unknown |
| `0x4D` | Unknown |
| `0x4E` | Unknown |
| `0x4F` | Unknown |
| `0x50` | Unknown |
| `0x51` | Unknown |
| `0x52` | Unknown |
| `0x53` | Dismiss Cover Sheet Home Screen Overlay From Pointer |
| `0x54` | Dismiss Cover Sheet Home Screen Overlay Scrunch |
| `0x55` | Unknown |
| `0x56` | Pan Banner |
| `0x57` | Dismiss Banner That Owns Home Affordance |
| `0x58` | Dismiss Banner That Owns Home Affordance From Pointer |
| `0x59` | Dismiss Banner That Owns Home Affordance Scrunch |
| `0x5A` | Dismiss Siri |
| `0x5B` | Dismiss Siri by Bottom Edge Pan |
| `0x5C` | Dismiss Siri by Pan |

### iOS 15.0

| Type | Static debug name |
| --- | --- |
| `0x0` | None |
| `0x1` | Show Cover Sheet |
| `0x2` | Dismiss Cover Sheet |
| `0x3` | Dismiss Cover Sheet More |
| `0x4` | Dismiss Secure App |
| `0x5` | Dismiss Long Look |
| `0x6` | Show ControlCenter |
| `0x7` | Show Control Center from Status Bar |
| `0x8` | Dismiss Control Center |
| `0x9` | Unknown |
| `0xA` | Show Control Center from Status Bar from Pointer |
| `0xB` | Dismiss Cover Sheet from Pointer |
| `0xC` | Dismiss Cover Sheet Scrunch |
| `0xD` | Dismiss Secure App from Pointer |
| `0xE` | Dismiss Secure App Scrunch |
| `0xF` | Dismiss Control Center From Pointer |
| `0x10` | Dismiss Control Center Scrunch |
| `0x11` | Scrunch |
| `0x12` | Floating Application Scrunch |
| `0x13` | Scene Resize |
| `0x14` | Legacy Scene Resize |
| `0x15` | Unpin Side Application |
| `0x16` | Present Right Floating Application |
| `0x17` | Present Left Floating Application |
| `0x18` | Unknown |
| `0x19` | Unknown |
| `0x1A` | Move Floating Application |
| `0x1B` | Pin Floating Application |
| `0x1C` | Floating Application Bottom Edge |
| `0x1D` | Dismiss Transient UI |
| `0x1E` | Dismiss Transient UI Indirect Pan |
| `0x1F` | Unhide Transient UI |
| `0x20` | Unhide Transient UI Double Tap |
| `0x21` | Dismiss Dock |
| `0x22` | Unknown |
| `0x23` | Unknown |
| `0x24` | Unknown |
| `0x25` | Present Right Floating Application From Pointer |
| `0x26` | Present Left Floating Application From Pointer |
| `0x27` | Dismiss Floating Application From Pointer |
| `0x28` | Switcher Force Press |
| `0x29` | Switcher Bottom Edge |
| `0x2A` | Dismiss Modal UI |
| `0x2B` | Dismiss Alert Item |
| `0x2C` | Click and Drag Home Gesture |
| `0x2D` | Dismiss Modal UI From Pointer |
| `0x2E` | Dismiss Modal UI Scrunch |
| `0x2F` | Dismiss Alert Item From Pointer |
| `0x30` | Dismiss Alert Item Scrunch |
| `0x31` | Unknown |
| `0x32` | Unknown |
| `0x33` | Unknown |
| `0x34` | Unknown |
| `0x35` | Unknown |
| `0x36` | Unknown |
| `0x37` | Unknown |
| `0x38` | CarPlay Banner Dismiss |
| `0x39` | Unknown |
| `0x3A` | Unknown |
| `0x3B` | Unknown |
| `0x3C` | Unknown |
| `0x3D` | Unknown |
| `0x3E` | Unknown |
| `0x3F` | Unknown |
| `0x40` | Unknown |
| `0x41` | Unknown |
| `0x42` | Unknown |
| `0x43` | Unknown |
| `0x44` | Unknown |
| `0x45` | Unknown |
| `0x46` | Unknown |
| `0x47` | Unknown |
| `0x48` | Unknown |
| `0x49` | Unknown |
| `0x4A` | Unknown |
| `0x4B` | Unknown |
| `0x4C` | Unknown |
| `0x4D` | Unknown |
| `0x4E` | Unknown |
| `0x4F` | Unknown |
| `0x50` | Unknown |
| `0x51` | Unknown |
| `0x52` | Dismiss Camera UI DashBoard |
| `0x53` | Dimiss Modal UI DashBoard |
| `0x54` | Dismiss Camera UI DashBoard From Pointer |
| `0x55` | Dismiss Camera UI DashBoard Scrunch |
| `0x56` | Home Affordance Bounce Tap |
| `0x57` | Home Affordance Reveal Tap |
| `0x58` | Home Affordance Reveal Double Tap |
| `0x59` | Home Affordance Reveal Edge Pan |
| `0x5A` | Unknown |
| `0x5B` | Unknown |
| `0x5C` | Dismiss Cover Sheet Home Screen Overlay From Pointer |
| `0x5D` | Dismiss Cover Sheet Home Screen Overlay Scrunch |
| `0x5E` | Unknown |
| `0x5F` | Pan Banner |
| `0x60` | Dismiss Banner That Owns Home Affordance |
| `0x61` | Dismiss Banner That Owns Home Affordance From Pointer |
| `0x62` | Dismiss Banner That Owns Home Affordance Scrunch |
| `0x63` | Dismiss Siri |
| `0x64` | Dismiss Siri by Bottom Edge Pan |
| `0x65` | Dismiss Siri by Pan |
| `0x66` | Present Notes PIP from Corner by Pencil |
| `0x67` | Present Notes PIP from Corner by Finger |
| `0x68` | Notes PIP Pan While Pinching |
| `0x69` | Notes PIP Pinch |
| `0x6A` | Notes PIP Rotate |

### iOS 16.0

| Type | Static debug name |
| --- | --- |
| `0x0` | None |
| `0x1` | Show Cover Sheet |
| `0x2` | Dismiss Cover Sheet |
| `0x3` | Dismiss Cover Sheet More |
| `0x4` | Dismiss Secure App |
| `0x5` | Dismiss Long Look |
| `0x6` | Show ControlCenter |
| `0x7` | Show Control Center from Status Bar |
| `0x8` | Dismiss Control Center |
| `0x9` | Unknown |
| `0xA` | Show Control Center from Status Bar from Pointer |
| `0xB` | Dismiss Cover Sheet from Pointer |
| `0xC` | Dismiss Cover Sheet Scrunch |
| `0xD` | Dismiss Secure App from Pointer |
| `0xE` | Dismiss Secure App Scrunch |
| `0xF` | Dismiss Control Center From Pointer |
| `0x10` | Dismiss Control Center Scrunch |
| `0x11` | Scrunch |
| `0x12` | Floating Application Scrunch |
| `0x13` | Bring Occluded Item Container Forward |
| `0x14` | Scene Resize |
| `0x15` | Legacy Scene Resize |
| `0x16` | Unpin Side Application |
| `0x17` | Present Right Floating Application |
| `0x18` | Present Left Floating Application |
| `0x19` | Unknown |
| `0x1A` | Unknown |
| `0x1B` | Move Floating Application |
| `0x1C` | Pin Floating Application |
| `0x1D` | Floating Application Bottom Edge |
| `0x1E` | Dismiss Transient UI |
| `0x1F` | Dismiss Transient UI Indirect Pan |
| `0x20` | Unhide Transient UI |
| `0x21` | Unhide Transient UI Double Tap |
| `0x22` | Unknown |
| `0x23` | Dismiss Dock |
| `0x24` | Unknown |
| `0x25` | Unknown |
| `0x26` | Unknown |
| `0x27` | Present Right Floating Application From Pointer |
| `0x28` | Present Left Floating Application From Pointer |
| `0x29` | Dismiss Floating Application From Pointer |
| `0x2A` | Switcher Force Press |
| `0x2B` | Switcher Bottom Edge |
| `0x2C` | Dismiss Modal UI |
| `0x2D` | Dismiss Alert Item |
| `0x2E` | Click and Drag Home Gesture |
| `0x2F` | Dismiss Modal UI From Pointer |
| `0x30` | Dismiss Modal UI Scrunch |
| `0x31` | Dismiss Alert Item From Pointer |
| `0x32` | Dismiss Alert Item Scrunch |
| `0x33` | Unknown |
| `0x34` | Reveal Continuous Expose Strips Pointer |
| `0x35` | Reveal Continuous Expose Strip Overflow Pointer |
| `0x36` | Reveal Continuous Expose Strip Overflow Drag |
| `0x37` | Unknown |
| `0x38` | Unknown |
| `0x39` | Unknown |
| `0x3A` | Unknown |
| `0x3B` | Unknown |
| `0x3C` | Unknown |
| `0x3D` | Unknown |
| `0x3E` | Unknown |
| `0x3F` | CarPlay Banner Dismiss |
| `0x40` | Unknown |
| `0x41` | Unknown |
| `0x42` | Unknown |
| `0x43` | Unknown |
| `0x44` | Unknown |
| `0x45` | Unknown |
| `0x46` | Unknown |
| `0x47` | Unknown |
| `0x48` | Unknown |
| `0x49` | Unknown |
| `0x4A` | Unknown |
| `0x4B` | Unknown |
| `0x4C` | Unknown |
| `0x4D` | Unknown |
| `0x4E` | Unknown |
| `0x4F` | Unknown |
| `0x50` | Unknown |
| `0x51` | Unknown |
| `0x52` | Unknown |
| `0x53` | Unknown |
| `0x54` | Unknown |
| `0x55` | Unknown |
| `0x56` | Unknown |
| `0x57` | Unknown |
| `0x58` | Unknown |
| `0x59` | Dismiss Camera UI DashBoard |
| `0x5A` | Dimiss Modal UI DashBoard |
| `0x5B` | Dismiss Camera UI DashBoard From Pointer |
| `0x5C` | Dismiss Camera UI DashBoard Scrunch |
| `0x5D` | Home Affordance Bounce Tap |
| `0x5E` | Home Affordance Reveal Tap |
| `0x5F` | Home Affordance Reveal Double Tap |
| `0x60` | Home Affordance Reveal Edge Pan |
| `0x61` | Unknown |
| `0x62` | Unknown |
| `0x63` | Unknown |
| `0x64` | Unknown |
| `0x65` | Unknown |
| `0x66` | Dismiss Cover Sheet Home Screen Overlay From Pointer |
| `0x67` | Dismiss Cover Sheet Home Screen Overlay Scrunch |
| `0x68` | Unknown |
| `0x69` | Pan Banner |
| `0x6A` | Dismiss Banner That Owns Home Affordance |
| `0x6B` | Dismiss Banner That Owns Home Affordance From Pointer |
| `0x6C` | Dismiss Banner That Owns Home Affordance Scrunch |
| `0x6D` | Dismiss Siri |
| `0x6E` | Dismiss Siri by Bottom Edge Pan |
| `0x6F` | Dismiss Siri by Pan |
| `0x70` | Present Notes PIP from Left Corner by Pencil |
| `0x71` | Present Notes PIP from Right Corner by Pencil |
| `0x72` | Present Notes PIP from Left Corner by Finger |
| `0x73` | Present Notes PIP from Right Corner by Finger |
| `0x74` | Notes PIP Pan While Pinching |
| `0x75` | Notes PIP Pinch |
| `0x76` | Notes PIP Rotate |
| `0x77` | Unknown |
| `0x78` | Unknown |
| `0x79` | Unknown |
| `0x7A` | Unknown |
| `0x7B` | Unknown |
| `0x7C` | Unknown |
| `0x7D` | Unknown |
| `0x7E` | Unknown |
| `0x7F` | System Aperture Resize |
| `0x80` | System Aperture Interaction |

### iOS 16.7

| Type | Static debug name |
| --- | --- |
| `0x0` | None |
| `0x1` | Show Cover Sheet |
| `0x2` | Dismiss Cover Sheet |
| `0x3` | Dismiss Cover Sheet More |
| `0x4` | Dismiss Secure App |
| `0x5` | Dismiss Long Look |
| `0x6` | Show ControlCenter |
| `0x7` | Show Control Center from Status Bar |
| `0x8` | Dismiss Control Center |
| `0x9` | Unknown |
| `0xA` | Show Control Center from Status Bar from Pointer |
| `0xB` | Dismiss Cover Sheet from Pointer |
| `0xC` | Dismiss Cover Sheet Scrunch |
| `0xD` | Dismiss Secure App from Pointer |
| `0xE` | Dismiss Secure App Scrunch |
| `0xF` | Dismiss Control Center From Pointer |
| `0x10` | Dismiss Control Center Scrunch |
| `0x11` | Scrunch |
| `0x12` | Floating Application Scrunch |
| `0x13` | Bring Occluded Item Container Forward |
| `0x14` | Scene Resize |
| `0x15` | Legacy Scene Resize |
| `0x16` | Unpin Side Application |
| `0x17` | Present Right Floating Application |
| `0x18` | Present Left Floating Application |
| `0x19` | Unknown |
| `0x1A` | Unknown |
| `0x1B` | Move Floating Application |
| `0x1C` | Pin Floating Application |
| `0x1D` | Floating Application Bottom Edge |
| `0x1E` | Dismiss Transient UI |
| `0x1F` | Dismiss Transient UI Indirect Pan |
| `0x20` | Unhide Transient UI |
| `0x21` | Unhide Transient UI Double Tap |
| `0x22` | Unknown |
| `0x23` | Dismiss Dock |
| `0x24` | Unknown |
| `0x25` | Unknown |
| `0x26` | Unknown |
| `0x27` | Present Right Floating Application From Pointer |
| `0x28` | Present Left Floating Application From Pointer |
| `0x29` | Dismiss Floating Application From Pointer |
| `0x2A` | Switcher Force Press |
| `0x2B` | Switcher Bottom Edge |
| `0x2C` | Dismiss Modal UI |
| `0x2D` | Dismiss Alert Item |
| `0x2E` | Click and Drag Home Gesture |
| `0x2F` | Dismiss Modal UI From Pointer |
| `0x30` | Dismiss Modal UI Scrunch |
| `0x31` | Dismiss Alert Item From Pointer |
| `0x32` | Dismiss Alert Item Scrunch |
| `0x33` | Unknown |
| `0x34` | Reveal Continuous Expose Strips Pointer |
| `0x35` | Reveal Continuous Expose Strip Overflow Pointer |
| `0x36` | Reveal Continuous Expose Strip Overflow Drag |
| `0x37` | Reveal Continuous Expose Strip Grabber Tongue |
| `0x38` | Unknown |
| `0x39` | Unknown |
| `0x3A` | Unknown |
| `0x3B` | Unknown |
| `0x3C` | Unknown |
| `0x3D` | Unknown |
| `0x3E` | Unknown |
| `0x3F` | Unknown |
| `0x40` | CarPlay Banner Dismiss |
| `0x41` | Unknown |
| `0x42` | Unknown |
| `0x43` | Unknown |
| `0x44` | Unknown |
| `0x45` | Unknown |
| `0x46` | Unknown |
| `0x47` | Unknown |
| `0x48` | Unknown |
| `0x49` | Unknown |
| `0x4A` | Unknown |
| `0x4B` | Unknown |
| `0x4C` | Unknown |
| `0x4D` | Unknown |
| `0x4E` | Unknown |
| `0x4F` | Unknown |
| `0x50` | Unknown |
| `0x51` | Unknown |
| `0x52` | Unknown |
| `0x53` | Unknown |
| `0x54` | Unknown |
| `0x55` | Unknown |
| `0x56` | Unknown |
| `0x57` | Unknown |
| `0x58` | Unknown |
| `0x59` | Unknown |
| `0x5A` | Dismiss Camera UI DashBoard |
| `0x5B` | Dismiss Modal UI DashBoard |
| `0x5C` | Dismiss Camera UI DashBoard From Pointer |
| `0x5D` | Dismiss Camera UI DashBoard Scrunch |
| `0x5E` | Home Affordance Bounce Tap |
| `0x5F` | Home Affordance Reveal Tap |
| `0x60` | Home Affordance Reveal Double Tap |
| `0x61` | Home Affordance Reveal Edge Pan |
| `0x62` | Unknown |
| `0x63` | Unknown |
| `0x64` | Unknown |
| `0x65` | Unknown |
| `0x66` | Unknown |
| `0x67` | Dismiss Cover Sheet Home Screen Overlay From Pointer |
| `0x68` | Dismiss Cover Sheet Home Screen Overlay Scrunch |
| `0x69` | Unknown |
| `0x6A` | Pan Banner |
| `0x6B` | Dismiss Banner That Owns Home Affordance |
| `0x6C` | Dismiss Banner That Owns Home Affordance From Pointer |
| `0x6D` | Dismiss Banner That Owns Home Affordance Scrunch |
| `0x6E` | Dismiss Siri |
| `0x6F` | Dismiss Siri by Bottom Edge Pan |
| `0x70` | Dismiss Siri by Pan |
| `0x71` | Present Notes PIP from Left Corner by Pencil |
| `0x72` | Present Notes PIP from Right Corner by Pencil |
| `0x73` | Present Notes PIP from Left Corner by Finger |
| `0x74` | Present Notes PIP from Right Corner by Finger |
| `0x75` | Notes PIP Pan While Pinching |
| `0x76` | Notes PIP Pinch |
| `0x77` | Notes PIP Rotate |
| `0x78` | Unknown |
| `0x79` | Unknown |
| `0x7A` | Unknown |
| `0x7B` | Unknown |
| `0x7C` | Unknown |
| `0x7D` | Unknown |
| `0x7E` | Unknown |
| `0x7F` | Unknown |
| `0x80` | System Aperture Resize |
| `0x81` | System Aperture Interaction |

### iOS 17.0

| Type | Static debug name |
| --- | --- |
| `0x0` | None |
| `0x1` | Show Cover Sheet |
| `0x2` | Dismiss Cover Sheet |
| `0x3` | Dismiss Cover Sheet More |
| `0x4` | Dismiss Secure App |
| `0x5` | Dismiss Long Look |
| `0x6` | Show ControlCenter |
| `0x7` | Show Control Center from Status Bar |
| `0x8` | Dismiss Control Center |
| `0x9` | Unknown |
| `0xA` | Show Control Center from Status Bar from Pointer |
| `0xB` | Dismiss Cover Sheet from Pointer |
| `0xC` | Dismiss Cover Sheet Scrunch |
| `0xD` | Dismiss Secure App from Pointer |
| `0xE` | Dismiss Secure App Scrunch |
| `0xF` | Dismiss Control Center From Pointer |
| `0x10` | Dismiss Control Center Scrunch |
| `0x11` | Scrunch |
| `0x12` | Floating Application Scrunch |
| `0x13` | Bring Occluded Item Container Forward |
| `0x14` | Click Down To Bring Occluded Item Container Forward |
| `0x15` | Scene Resize |
| `0x16` | Legacy Scene Resize |
| `0x17` | Unpin Side Application |
| `0x18` | Present Right Floating Application |
| `0x19` | Present Left Floating Application |
| `0x1A` | Unknown |
| `0x1B` | Unknown |
| `0x1C` | Move Floating Application |
| `0x1D` | Pin Floating Application |
| `0x1E` | Move Floating Application (Client Relationship) |
| `0x1F` | Floating Application Bottom Edge |
| `0x20` | Dismiss Transient UI |
| `0x21` | Dismiss Transient UI Indirect Pan |
| `0x22` | Unhide Transient UI |
| `0x23` | Unhide Transient UI Double Tap |
| `0x24` | Unknown |
| `0x25` | Dismiss Dock |
| `0x26` | Unknown |
| `0x27` | Unknown |
| `0x28` | Unknown |
| `0x29` | Present Right Floating Application From Pointer |
| `0x2A` | Present Left Floating Application From Pointer |
| `0x2B` | Dismiss Floating Application From Pointer |
| `0x2C` | Switcher Force Press |
| `0x2D` | Switcher Bottom Edge |
| `0x2E` | Dismiss Modal UI |
| `0x2F` | Dismiss Alert Item |
| `0x30` | Click and Drag Home Gesture |
| `0x31` | Dismiss Modal UI From Pointer |
| `0x32` | Dismiss Modal UI Scrunch |
| `0x33` | Dismiss Alert Item From Pointer |
| `0x34` | Dismiss Alert Item Scrunch |
| `0x35` | Unknown |
| `0x36` | Reveal Continuous Expose Strips Pointer |
| `0x37` | Reveal Continuous Expose Strip Overflow Pointer |
| `0x38` | Reveal Continuous Expose Strip Overflow Drag |
| `0x39` | Reveal Continuous Expose Strip Grabber Tongue |
| `0x3A` | Unknown |
| `0x3B` | Unknown |
| `0x3C` | Unknown |
| `0x3D` | Unknown |
| `0x3E` | Unknown |
| `0x3F` | Unknown |
| `0x40` | Unknown |
| `0x41` | Unknown |
| `0x42` | CarPlay Banner Dismiss |
| `0x43` | Unknown |
| `0x44` | Unknown |
| `0x45` | Unknown |
| `0x46` | Unknown |
| `0x47` | Unknown |
| `0x48` | Unknown |
| `0x49` | Unknown |
| `0x4A` | Unknown |
| `0x4B` | Unknown |
| `0x4C` | Unknown |
| `0x4D` | Unknown |
| `0x4E` | Unknown |
| `0x4F` | Unknown |
| `0x50` | Unknown |
| `0x51` | Unknown |
| `0x52` | Unknown |
| `0x53` | Unknown |
| `0x54` | Unknown |
| `0x55` | Unknown |
| `0x56` | Unknown |
| `0x57` | Unknown |
| `0x58` | Unknown |
| `0x59` | Unknown |
| `0x5A` | Unknown |
| `0x5B` | Unknown |
| `0x5C` | Dismiss Camera UI DashBoard |
| `0x5D` | Dismiss Modal UI DashBoard |
| `0x5E` | Dismiss Camera UI DashBoard From Pointer |
| `0x5F` | Dismiss Camera UI DashBoard Scrunch |
| `0x60` | Home Affordance Bounce Tap |
| `0x61` | Home Affordance Reveal Tap |
| `0x62` | Home Affordance Reveal Double Tap |
| `0x63` | Home Affordance Reveal Edge Pan |
| `0x64` | Unknown |
| `0x65` | Unknown |
| `0x66` | Unknown |
| `0x67` | Unknown |
| `0x68` | Unknown |
| `0x69` | Dismiss Cover Sheet Home Screen Overlay From Pointer |
| `0x6A` | Dismiss Cover Sheet Home Screen Overlay Scrunch |
| `0x6B` | Unknown |
| `0x6C` | Pan Banner |
| `0x6D` | Dismiss Banner That Owns Home Affordance |
| `0x6E` | Dismiss Banner That Owns Home Affordance From Pointer |
| `0x6F` | Dismiss Banner That Owns Home Affordance Scrunch |
| `0x70` | Dismiss Siri |
| `0x71` | Dismiss Siri by Bottom Edge Pan |
| `0x72` | Dismiss Siri by Pan |
| `0x73` | Present Notes PIP from Left Corner by Pencil |
| `0x74` | Present Notes PIP from Right Corner by Pencil |
| `0x75` | Present Notes PIP from Left Corner by Finger |
| `0x76` | Present Notes PIP from Right Corner by Finger |
| `0x77` | Notes PIP Pan While Pinching |
| `0x78` | Notes PIP Pinch |
| `0x79` | Notes PIP Rotate |
| `0x7A` | Unknown |
| `0x7B` | Unknown |
| `0x7C` | Unknown |
| `0x7D` | Unknown |
| `0x7E` | Unknown |
| `0x7F` | Unknown |
| `0x80` | Unknown |
| `0x81` | Unknown |
| `0x82` | System Aperture Resize |
| `0x83` | System Aperture Interaction |

### iOS 17.4

| Type | Static debug name |
| --- | --- |
| `0x0` | None |
| `0x1` | Show Cover Sheet |
| `0x2` | Dismiss Cover Sheet |
| `0x3` | Dismiss Cover Sheet More |
| `0x4` | Dismiss Secure App |
| `0x5` | Dismiss Long Look |
| `0x6` | Show ControlCenter |
| `0x7` | Show Control Center from Status Bar |
| `0x8` | Dismiss Control Center |
| `0x9` | Unknown |
| `0xA` | Show Control Center from Status Bar from Pointer |
| `0xB` | Dismiss Cover Sheet from Pointer |
| `0xC` | Dismiss Cover Sheet Scrunch |
| `0xD` | Dismiss Secure App from Pointer |
| `0xE` | Dismiss Secure App Scrunch |
| `0xF` | Dismiss Control Center From Pointer |
| `0x10` | Dismiss Control Center Scrunch |
| `0x11` | Dismiss SystemUI Scene |
| `0x12` | Scrunch |
| `0x13` | Floating Application Scrunch |
| `0x14` | Bring Occluded Item Container Forward |
| `0x15` | Click Down To Bring Occluded Item Container Forward |
| `0x16` | Scene Resize |
| `0x17` | Legacy Scene Resize |
| `0x18` | Unpin Side Application |
| `0x19` | Present Right Floating Application |
| `0x1A` | Present Left Floating Application |
| `0x1B` | Unknown |
| `0x1C` | Unknown |
| `0x1D` | Move Floating Application |
| `0x1E` | Pin Floating Application |
| `0x1F` | Move Floating Application (Client Relationship) |
| `0x20` | Floating Application Bottom Edge |
| `0x21` | Dismiss Transient UI |
| `0x22` | Dismiss Transient UI Indirect Pan |
| `0x23` | Unhide Transient UI |
| `0x24` | Unhide Transient UI Double Tap |
| `0x25` | Unknown |
| `0x26` | Dismiss Dock |
| `0x27` | Unknown |
| `0x28` | Unknown |
| `0x29` | Unknown |
| `0x2A` | Present Right Floating Application From Pointer |
| `0x2B` | Present Left Floating Application From Pointer |
| `0x2C` | Dismiss Floating Application From Pointer |
| `0x2D` | Switcher Bottom Edge |
| `0x2E` | Dismiss Modal UI |
| `0x2F` | Dismiss Alert Item |
| `0x30` | Click and Drag Home Gesture |
| `0x31` | Dismiss Modal UI From Pointer |
| `0x32` | Dismiss Modal UI Scrunch |
| `0x33` | Dismiss Alert Item From Pointer |
| `0x34` | Dismiss Alert Item Scrunch |
| `0x35` | Unknown |
| `0x36` | Reveal Continuous Expose Strips Pointer |
| `0x37` | Reveal Continuous Expose Strip Overflow Pointer |
| `0x38` | Reveal Continuous Expose Strip Overflow Drag |
| `0x39` | Reveal Continuous Expose Strip Grabber Tongue |
| `0x3A` | Unknown |
| `0x3B` | Unknown |
| `0x3C` | Unknown |
| `0x3D` | Unknown |
| `0x3E` | Unknown |
| `0x3F` | Unknown |
| `0x40` | Unknown |
| `0x41` | Unknown |
| `0x42` | CarPlay Banner Dismiss |
| `0x43` | Unknown |
| `0x44` | Unknown |
| `0x45` | Unknown |
| `0x46` | Unknown |
| `0x47` | Unknown |
| `0x48` | Unknown |
| `0x49` | Unknown |
| `0x4A` | Unknown |
| `0x4B` | Unknown |
| `0x4C` | Unknown |
| `0x4D` | Unknown |
| `0x4E` | Unknown |
| `0x4F` | Unknown |
| `0x50` | Unknown |
| `0x51` | Unknown |
| `0x52` | Unknown |
| `0x53` | Unknown |
| `0x54` | Unknown |
| `0x55` | Unknown |
| `0x56` | Unknown |
| `0x57` | Unknown |
| `0x58` | Unknown |
| `0x59` | Unknown |
| `0x5A` | Unknown |
| `0x5B` | Unknown |
| `0x5C` | Dismiss Camera UI DashBoard |
| `0x5D` | Dismiss Modal UI DashBoard |
| `0x5E` | Dismiss Camera UI DashBoard From Pointer |
| `0x5F` | Dismiss Camera UI DashBoard Scrunch |
| `0x60` | Home Affordance Bounce Tap |
| `0x61` | Home Affordance Reveal Tap |
| `0x62` | Home Affordance Reveal Double Tap |
| `0x63` | Home Affordance Reveal Edge Pan |
| `0x64` | Unknown |
| `0x65` | Unknown |
| `0x66` | Unknown |
| `0x67` | Unknown |
| `0x68` | Unknown |
| `0x69` | Dismiss Cover Sheet Home Screen Overlay From Pointer |
| `0x6A` | Dismiss Cover Sheet Home Screen Overlay Scrunch |
| `0x6B` | Unknown |
| `0x6C` | Pan Banner |
| `0x6D` | Dismiss Banner That Owns Home Affordance |
| `0x6E` | Dismiss Banner That Owns Home Affordance From Pointer |
| `0x6F` | Dismiss Banner That Owns Home Affordance Scrunch |
| `0x70` | Dismiss Siri |
| `0x71` | Dismiss Siri by Bottom Edge Pan |
| `0x72` | Dismiss Siri by Pan |
| `0x73` | Present Notes PIP from Left Corner by Pencil |
| `0x74` | Present Notes PIP from Right Corner by Pencil |
| `0x75` | Present Notes PIP from Left Corner by Finger |
| `0x76` | Present Notes PIP from Right Corner by Finger |
| `0x77` | Notes PIP Pan While Pinching |
| `0x78` | Notes PIP Pinch |
| `0x79` | Notes PIP Rotate |
| `0x7A` | Unknown |
| `0x7B` | Unknown |
| `0x7C` | Unknown |
| `0x7D` | Unknown |
| `0x7E` | Unknown |
| `0x7F` | Unknown |
| `0x80` | Unknown |
| `0x81` | Unknown |
| `0x82` | System Aperture Resize |
| `0x83` | System Aperture Interaction |

### iOS 18.0

| Type | Static debug name |
| --- | --- |
| `0x0` | None |
| `0x1` | Show Cover Sheet |
| `0x2` | Dismiss Cover Sheet |
| `0x3` | Dismiss Cover Sheet More |
| `0x4` | Dismiss Secure App |
| `0x5` | Dismiss Long Look |
| `0x6` | Show ControlCenter |
| `0x7` | Show Control Center from Status Bar |
| `0x8` | Dismiss Control Center |
| `0x9` | Unknown |
| `0xA` | Show Control Center from Status Bar from Pointer |
| `0xB` | Dismiss Cover Sheet from Pointer |
| `0xC` | Dismiss Cover Sheet Scrunch |
| `0xD` | Dismiss Secure App from Pointer |
| `0xE` | Dismiss Secure App Scrunch |
| `0xF` | Dismiss Control Center From Pointer |
| `0x10` | Dismiss Control Center Scrunch |
| `0x11` | Dismiss SystemUI Scene |
| `0x12` | Scrunch |
| `0x13` | Floating Application Scrunch |
| `0x14` | Bring Occluded Item Container Forward |
| `0x15` | Click Down To Bring Occluded Item Container Forward |
| `0x16` | Scene Resize |
| `0x17` | Legacy Scene Resize |
| `0x18` | Unpin Side Application |
| `0x19` | Present Right Floating Application |
| `0x1A` | Present Left Floating Application |
| `0x1B` | Unknown |
| `0x1C` | Unknown |
| `0x1D` | Move Floating Application |
| `0x1E` | Pin Floating Application |
| `0x1F` | Move Floating Application (Client Relationship) |
| `0x20` | Floating Application Bottom Edge |
| `0x21` | Dismiss Transient UI |
| `0x22` | Dismiss Transient UI Indirect Pan |
| `0x23` | Unhide Transient UI |
| `0x24` | Unhide Transient UI Double Tap |
| `0x25` | Unknown |
| `0x26` | Dismiss Dock |
| `0x27` | Unknown |
| `0x28` | Unknown |
| `0x29` | Unknown |
| `0x2A` | Present Right Floating Application From Pointer |
| `0x2B` | Present Left Floating Application From Pointer |
| `0x2C` | Dismiss Floating Application From Pointer |
| `0x2D` | Switcher Bottom Edge |
| `0x2E` | Dismiss Modal UI |
| `0x2F` | Dismiss Alert Item |
| `0x30` | Click and Drag Home Gesture |
| `0x31` | Dismiss Modal UI From Pointer |
| `0x32` | Dismiss Modal UI Scrunch |
| `0x33` | Dismiss Alert Item From Pointer |
| `0x34` | Dismiss Alert Item Scrunch |
| `0x35` | Unknown |
| `0x36` | Reveal Continuous Expose Strips Pointer |
| `0x37` | Reveal Continuous Expose Strip Overflow Pointer |
| `0x38` | Reveal Continuous Expose Strip Overflow Drag |
| `0x39` | Reveal Continuous Expose Strip Grabber Tongue |
| `0x3A` | Unknown |
| `0x3B` | Unknown |
| `0x3C` | Unknown |
| `0x3D` | Unknown |
| `0x3E` | Unknown |
| `0x3F` | Unknown |
| `0x40` | Unknown |
| `0x41` | CarPlay Banner Dismiss |
| `0x42` | Unknown |
| `0x43` | Unknown |
| `0x44` | Unknown |
| `0x45` | Unknown |
| `0x46` | Unknown |
| `0x47` | Unknown |
| `0x48` | Unknown |
| `0x49` | Unknown |
| `0x4A` | Unknown |
| `0x4B` | Unknown |
| `0x4C` | Unknown |
| `0x4D` | Unknown |
| `0x4E` | Unknown |
| `0x4F` | Unknown |
| `0x50` | Unknown |
| `0x51` | Unknown |
| `0x52` | Unknown |
| `0x53` | Unknown |
| `0x54` | Unknown |
| `0x55` | Unknown |
| `0x56` | Unknown |
| `0x57` | Unknown |
| `0x58` | Unknown |
| `0x59` | Unknown |
| `0x5A` | Unknown |
| `0x5B` | Unknown |
| `0x5C` | Dismiss Camera UI DashBoard |
| `0x5D` | Dismiss Modal UI DashBoard |
| `0x5E` | Dismiss Camera UI DashBoard From Pointer |
| `0x5F` | Dismiss Camera UI DashBoard Scrunch |
| `0x60` | Home Affordance Bounce Tap |
| `0x61` | Home Affordance Bounce Double Tap |
| `0x62` | Home Affordance Bounce Double Tap Failure |
| `0x63` | Home Affordance Reveal Tap |
| `0x64` | Home Affordance Reveal Double Tap |
| `0x65` | Home Affordance Reveal Edge Pan |
| `0x66` | Unknown |
| `0x67` | Unknown |
| `0x68` | Unknown |
| `0x69` | Unknown |
| `0x6A` | Unknown |
| `0x6B` | Dismiss Cover Sheet Home Screen Overlay From Pointer |
| `0x6C` | Dismiss Cover Sheet Home Screen Overlay Scrunch |
| `0x6D` | Unknown |
| `0x6E` | Pan Banner |
| `0x6F` | Dismiss Banner That Owns Home Affordance |
| `0x70` | Dismiss Banner That Owns Home Affordance From Pointer |
| `0x71` | Dismiss Banner That Owns Home Affordance Scrunch |
| `0x72` | Dismiss Siri |
| `0x73` | Dismiss Siri by Bottom Edge Pan |
| `0x74` | Dismiss Siri by Pan |
| `0x75` | Present Notes PIP from Left Corner by Pencil |
| `0x76` | Present Notes PIP from Right Corner by Pencil |
| `0x77` | Present Notes PIP from Left Corner by Finger |
| `0x78` | Present Notes PIP from Right Corner by Finger |
| `0x79` | Notes PIP Pan While Pinching |
| `0x7A` | Notes PIP Pinch |
| `0x7B` | Notes PIP Rotate |
| `0x7C` | Unknown |
| `0x7D` | Unknown |
| `0x7E` | Unknown |
| `0x7F` | Unknown |
| `0x80` | Unknown |
| `0x81` | Unknown |
| `0x82` | Unknown |
| `0x83` | Unknown |
| `0x84` | System Aperture Resize |
| `0x85` | System Aperture Interaction |

### iOS 18.3

| Type | Static debug name |
| --- | --- |
| `0x0` | Show Control Center from Status Bar from Pointer |
| `0x1` | Show Cover Sheet |
| `0x2` | Dismiss Cover Sheet |
| `0x3` | Dismiss Cover Sheet More |
| `0x4` | Dismiss Secure App |
| `0x5` | Dismiss Long Look |
| `0x6` | Show ControlCenter |
| `0x7` | Show Control Center from Status Bar |
| `0x8` | Dismiss Control Center |
| `0x9` | Unknown |
| `0xA` | Show Control Center from Status Bar from Pointer |
| `0xB` | Dismiss Cover Sheet from Pointer |
| `0xC` | Dismiss Cover Sheet Scrunch |
| `0xD` | Dismiss Secure App from Pointer |
| `0xE` | Dismiss Secure App Scrunch |
| `0xF` | Dismiss Control Center From Pointer |
| `0x10` | Dismiss Control Center Scrunch |
| `0x11` | Dismiss SystemUI Scene |
| `0x12` | Scrunch |
| `0x13` | Floating Application Scrunch |
| `0x14` | Bring Occluded Item Container Forward |
| `0x15` | Click Down To Bring Occluded Item Container Forward |
| `0x16` | Scene Resize |
| `0x17` | Legacy Scene Resize |
| `0x18` | Unpin Side Application |
| `0x19` | Present Right Floating Application |
| `0x1A` | Present Left Floating Application |
| `0x1B` | Unknown |
| `0x1C` | Unknown |
| `0x1D` | Move Floating Application |
| `0x1E` | Pin Floating Application |
| `0x1F` | Move Floating Application (Client Relationship) |
| `0x20` | Floating Application Bottom Edge |
| `0x21` | Dismiss Transient UI |
| `0x22` | Dismiss Transient UI Indirect Pan |
| `0x23` | Unhide Transient UI |
| `0x24` | Unhide Transient UI Double Tap |
| `0x25` | Unknown |
| `0x26` | Dismiss Dock |
| `0x27` | Unknown |
| `0x28` | Unknown |
| `0x29` | Unknown |
| `0x2A` | Present Right Floating Application From Pointer |
| `0x2B` | Present Left Floating Application From Pointer |
| `0x2C` | Dismiss Floating Application From Pointer |
| `0x2D` | Switcher Bottom Edge |
| `0x2E` | Dismiss Modal UI |
| `0x2F` | Dismiss Alert Item |
| `0x30` | Click and Drag Home Gesture |
| `0x31` | Dismiss Modal UI From Pointer |
| `0x32` | Dismiss Modal UI Scrunch |
| `0x33` | Dismiss Alert Item From Pointer |
| `0x34` | Dismiss Alert Item Scrunch |
| `0x35` | Unknown |
| `0x36` | Reveal Continuous Expose Strips Pointer |
| `0x37` | Reveal Continuous Expose Strip Overflow Pointer |
| `0x38` | Reveal Continuous Expose Strip Overflow Drag |
| `0x39` | Reveal Continuous Expose Strip Grabber Tongue |
| `0x3A` | Unknown |
| `0x3B` | Unknown |
| `0x3C` | Unknown |
| `0x3D` | Unknown |
| `0x3E` | Unknown |
| `0x3F` | Unknown |
| `0x40` | Unknown |
| `0x41` | CarPlay Banner Dismiss |
| `0x42` | Unknown |
| `0x43` | Unknown |
| `0x44` | Unknown |
| `0x45` | Unknown |
| `0x46` | Unknown |
| `0x47` | Unknown |
| `0x48` | Unknown |
| `0x49` | Unknown |
| `0x4A` | Unknown |
| `0x4B` | Unknown |
| `0x4C` | Unknown |
| `0x4D` | Unknown |
| `0x4E` | Unknown |
| `0x4F` | Unknown |
| `0x50` | Unknown |
| `0x51` | Unknown |
| `0x52` | Unknown |
| `0x53` | Unknown |
| `0x54` | Unknown |
| `0x55` | Unknown |
| `0x56` | Unknown |
| `0x57` | Unknown |
| `0x58` | Unknown |
| `0x59` | Unknown |
| `0x5A` | Unknown |
| `0x5B` | Unknown |
| `0x5C` | Dismiss Camera UI DashBoard |
| `0x5D` | Dismiss Modal UI DashBoard |
| `0x5E` | Dismiss Camera UI DashBoard From Pointer |
| `0x5F` | Dismiss Camera UI DashBoard Scrunch |
| `0x60` | Home Affordance Bounce Tap |
| `0x61` | Home Affordance Bounce Double Tap |
| `0x62` | Home Affordance Bounce Double Tap Failure |
| `0x63` | Home Affordance Reveal Tap |
| `0x64` | Home Affordance Reveal Double Tap |
| `0x65` | Home Affordance Reveal Edge Pan |
| `0x66` | Unknown |
| `0x67` | Unknown |
| `0x68` | Unknown |
| `0x69` | Unknown |
| `0x6A` | Unknown |
| `0x6B` | Dismiss Cover Sheet Home Screen Overlay From Pointer |
| `0x6C` | Dismiss Cover Sheet Home Screen Overlay Scrunch |
| `0x6D` | Unknown |
| `0x6E` | Pan Banner |
| `0x6F` | Dismiss Banner That Owns Home Affordance |
| `0x70` | Dismiss Banner That Owns Home Affordance From Pointer |
| `0x71` | Dismiss Banner That Owns Home Affordance Scrunch |
| `0x72` | Dismiss Siri |
| `0x73` | Dismiss Siri by Bottom Edge Pan |
| `0x74` | Dismiss Siri by Pan |
| `0x75` | Present Notes PIP from Left Corner by Pencil |
| `0x76` | Present Notes PIP from Right Corner by Pencil |
| `0x77` | Present Notes PIP from Left Corner by Finger |
| `0x78` | Present Notes PIP from Right Corner by Finger |
| `0x79` | Notes PIP Pan While Pinching |
| `0x7A` | Notes PIP Pinch |
| `0x7B` | Notes PIP Rotate |
| `0x7C` | Unknown |
| `0x7D` | Unknown |
| `0x7E` | Unknown |
| `0x7F` | Unknown |
| `0x80` | Unknown |
| `0x81` | Unknown |
| `0x82` | Unknown |
| `0x83` | Unknown |
| `0x84` | System Aperture Resize |
| `0x85` | System Aperture Interaction |

### iOS 26.0 and 26.0.1

| Type | Static debug name |
| --- | --- |
| `0x0` | None |
| `0x1` | Show Cover Sheet |
| `0x2` | Dismiss Cover Sheet |
| `0x3` | Dismiss Cover Sheet More |
| `0x4` | Dismiss Secure App |
| `0x5` | Dismiss Long Look |
| `0x6` | Unknown |
| `0x7` | Dismiss Cover Sheet from Pointer |
| `0x8` | Dismiss Cover Sheet Scrunch |
| `0x9` | Dismiss Secure App from Pointer |
| `0xA` | Dismiss Secure App Scrunch |
| `0xB` | Dismiss SystemUI Scene |
| `0xC` | Scrunch |
| `0xD` | Floating Application Scrunch |
| `0xE` | Bring Occluded Item Container Forward |
| `0xF` | Click Down To Bring Occluded Item Container Forward |
| `0x10` | Scene Resize |
| `0x11` | Legacy Scene Resize |
| `0x12` | Unpin Side Application |
| `0x13` | Present Right Floating Application |
| `0x14` | Present Left Floating Application |
| `0x15` | Unknown |
| `0x16` | Unknown |
| `0x17` | Move Floating Application |
| `0x18` | Pin Floating Application |
| `0x19` | Move Floating Application (Client Relationship) |
| `0x1A` | Floating Application Bottom Edge |
| `0x1B` | Dismiss Transient UI |
| `0x1C` | Dismiss Transient UI Indirect Pan |
| `0x1D` | Unhide Transient UI |
| `0x1E` | Unhide Transient UI Double Tap |
| `0x1F` | Unknown |
| `0x20` | Dismiss Dock |
| `0x21` | Unknown |
| `0x22` | Unknown |
| `0x23` | Unknown |
| `0x24` | Present Right Floating Application From Pointer |
| `0x25` | Present Left Floating Application From Pointer |
| `0x26` | Dismiss Floating Application From Pointer |
| `0x27` | Switcher Bottom Edge |
| `0x28` | Dismiss Modal UI |
| `0x29` | Dismiss Alert Item |
| `0x2A` | Click and Drag Home Gesture |
| `0x2B` | Dismiss Modal UI From Pointer |
| `0x2C` | Dismiss Modal UI Scrunch |
| `0x2D` | Dismiss Alert Item From Pointer |
| `0x2E` | Dismiss Alert Item Scrunch |
| `0x2F` | Unknown |
| `0x30` | Reveal Continuous Expose Strips Pointer |
| `0x31` | Reveal Continuous Expose Strip Overflow Pointer |
| `0x32` | Reveal Continuous Expose Strip Overflow Drag |
| `0x33` | Reveal Continuous Expose Strip Grabber Tongue |
| `0x34` | User Click In App Interaction |
| `0x35` | Unknown |
| `0x36` | Unknown |
| `0x37` | Unknown |
| `0x38` | Show ControlCenter |
| `0x39` | Show Control Center from Status Bar |
| `0x3A` | Show Control Center from Status Bar from Pointer |
| `0x3B` | Dismiss Control Center |
| `0x3C` | Dismiss Control Center Outside Content Interaction (Tap) |
| `0x3D` | Dismiss Control Center Outside Content Interaction (Pan) |
| `0x3E` | Dismiss Control Center From Pointer |
| `0x3F` | Dismiss Control Center Scrunch |
| `0x40` | Unknown |
| `0x41` | Unknown |
| `0x42` | Unknown |
| `0x43` | Unknown |
| `0x44` | CarPlay Banner Dismiss |
| `0x45` | Unknown |
| `0x46` | Unknown |
| `0x47` | Unknown |
| `0x48` | Unknown |
| `0x49` | Unknown |
| `0x4A` | Unknown |
| `0x4B` | Unknown |
| `0x4C` | Unknown |
| `0x4D` | Unknown |
| `0x4E` | Unknown |
| `0x4F` | Unknown |
| `0x50` | Unknown |
| `0x51` | Unknown |
| `0x52` | Unknown |
| `0x53` | Unknown |
| `0x54` | Unknown |
| `0x55` | Unknown |
| `0x56` | Unknown |
| `0x57` | Unknown |
| `0x58` | Unknown |
| `0x59` | Unknown |
| `0x5A` | Unknown |
| `0x5B` | Unknown |
| `0x5C` | Unknown |
| `0x5D` | Unknown |
| `0x5E` | Unknown |
| `0x5F` | Dismiss Camera UI DashBoard |
| `0x60` | Dismiss Modal UI DashBoard |
| `0x61` | Dismiss Camera UI DashBoard From Pointer |
| `0x62` | Dismiss Camera UI DashBoard Scrunch |
| `0x63` | Home Affordance Bounce Tap |
| `0x64` | Home Affordance Bounce Double Tap |
| `0x65` | Home Affordance Bounce Double Tap Failure |
| `0x66` | Home Affordance Reveal Tap |
| `0x67` | Home Affordance Reveal Double Tap |
| `0x68` | Home Affordance Reveal Edge Pan |
| `0x69` | Unknown |
| `0x6A` | Unknown |
| `0x6B` | Unknown |
| `0x6C` | Unknown |
| `0x6D` | Unknown |
| `0x6E` | Dismiss Cover Sheet Home Screen Overlay From Pointer |
| `0x6F` | Dismiss Cover Sheet Home Screen Overlay Scrunch |
| `0x70` | Unknown |
| `0x71` | Pan Banner |
| `0x72` | Dismiss Banner That Owns Home Affordance |
| `0x73` | Dismiss Banner That Owns Home Affordance From Pointer |
| `0x74` | Dismiss Banner That Owns Home Affordance Scrunch |
| `0x75` | Dismiss Siri |
| `0x76` | Dismiss Siri by Bottom Edge Pan |
| `0x77` | Dismiss Siri by Pan |
| `0x78` | Present Notes PIP from Left Corner by Pencil |
| `0x79` | Present Notes PIP from Right Corner by Pencil |
| `0x7A` | Present Notes PIP from Left Corner by Finger |
| `0x7B` | Present Notes PIP from Right Corner by Finger |
| `0x7C` | Notes PIP Pan While Pinching |
| `0x7D` | Notes PIP Pinch |
| `0x7E` | Notes PIP Rotate |
| `0x7F` | Unknown |
| `0x80` | Unknown |
| `0x81` | Unknown |
| `0x82` | Unknown |
| `0x83` | Unknown |
| `0x84` | Unknown |
| `0x85` | Unknown |
| `0x86` | Unknown |
| `0x87` | System Aperture Resize |
| `0x88` | System Aperture Interaction |
| `0x89` | Unknown |
| `0x8A` | Unknown |
| `0x8B` | Unknown |
| `0x8C` | Unknown |
| `0x8D` | Show Menu Bar |
| `0x8E` | Show Menu Bar From Pointer |
| `0x8F` | Dismiss Menu Bar From Pointer |
| `0x90` | Unknown |
| `0x91` | Window Top Region Double Tap |
| `0x92` | Window Scroll-to-Top Tap |

