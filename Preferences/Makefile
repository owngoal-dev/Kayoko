BUNDLE_NAME += KayokoPreferences

KayokoPreferences_USE_MODULES := 0

KayokoPreferences_FILES += $(wildcard Controllers/*.m Cells/*.m Utilities/*.m)
KayokoPreferences_FILES += $(wildcard ../Shared/Tags/*.m)
KayokoPreferences_FILES += $(wildcard ../Shared/Purchases/*.m)

KayokoPreferences_CFLAGS += -fobjc-arc
KayokoPreferences_CFLAGS += -I.
KayokoPreferences_CFLAGS += -I../Preferences
KayokoPreferences_CFLAGS += -IControllers
KayokoPreferences_CFLAGS += -ICells
KayokoPreferences_CFLAGS += -IUtilities
KayokoPreferences_CFLAGS += -I../Shared/Tags
KayokoPreferences_CFLAGS += -I../Shared/Purchases
KayokoPreferences_CFLAGS += -I../Shared

KayokoPreferences_FRAMEWORKS += CoreGraphics
KayokoPreferences_FRAMEWORKS += QuartzCore
KayokoPreferences_FRAMEWORKS += Security
KayokoPreferences_FRAMEWORKS += UIKit

ifeq ($(THEOS_DEVICE_SIMULATOR),1)
KayokoPreferences_CFLAGS += -F/opt/simject
KayokoPreferences_LDFLAGS += -FFrameworks/_Simulator -F/opt/simject -rpath /opt/simject
else ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
KayokoPreferences_CFLAGS += -FFrameworks/_rootless
KayokoPreferences_LDFLAGS += -FFrameworks/_rootless
else ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
KayokoPreferences_CFLAGS += -FFrameworks/_roothide
KayokoPreferences_LDFLAGS += -FFrameworks/_roothide
else
KayokoPreferences_CFLAGS += -FFrameworks
KayokoPreferences_LDFLAGS += -FFrameworks
endif

KayokoPreferences_EXTRA_FRAMEWORKS += AltList
KayokoPreferences_PRIVATE_FRAMEWORKS += Preferences
ifneq ($(THEOS_DEVICE_SIMULATOR),1)
KayokoPreferences_PRIVATE_FRAMEWORKS += FrontBoardServices
KayokoPreferences_PRIVATE_FRAMEWORKS += SpringBoardServices
endif

ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
KayokoPreferences_LIBRARIES += roothide
endif

KayokoPreferences_INSTALL_PATH := /Library/PreferenceBundles

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/bundle.mk
