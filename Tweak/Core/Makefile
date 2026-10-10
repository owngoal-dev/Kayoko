TWEAK_NAME := KayokoCore

KayokoCore_USE_MODULES := 0

KayokoCore_FILES += KayokoCore.m
KayokoCore_FILES += KayokoCoreRuntime.m
KayokoCore_FILES += KayokoKeyboardHostResolver.m
KayokoCore_FILES += KayokoSpringBoardHooks.m
KayokoCore_FILES += KayokoPasteTipHooks.m
KayokoCore_FILES += ../Helper/KayokoSwipeUpGestureRecognizer.m
KayokoCore_FILES += $(wildcard Manager/*.m Actions/*.m Controllers/*.m Coordinators/*.m DataSources/*.m Models/*.m Presentation/*.m Views/*.m)
KayokoCore_FILES += $(wildcard ../../Shared/Tags/*.m)
KayokoCore_FILES += $(wildcard ../../Shared/Purchases/*.m)

KayokoCore_CFLAGS += -fobjc-arc
KayokoCore_CFLAGS += -I.
KayokoCore_CFLAGS += -IManager
KayokoCore_CFLAGS += -I../../Preferences
KayokoCore_CFLAGS += -I../Helper
KayokoCore_CFLAGS += -IActions
KayokoCore_CFLAGS += -IControllers
KayokoCore_CFLAGS += -ICoordinators
KayokoCore_CFLAGS += -IDataSources
KayokoCore_CFLAGS += -IModels
KayokoCore_CFLAGS += -IPresentation
KayokoCore_CFLAGS += -IViews
KayokoCore_CFLAGS += -I../../Shared/Tags
KayokoCore_CFLAGS += -I../../Shared/Purchases
KayokoCore_CFLAGS += -I../../Shared

KayokoCore_FRAMEWORKS += AudioToolbox
KayokoCore_FRAMEWORKS += AVFoundation
KayokoCore_FRAMEWORKS += CoreGraphics
KayokoCore_FRAMEWORKS += ImageIO
KayokoCore_FRAMEWORKS += IOKit
KayokoCore_FRAMEWORKS += QuartzCore
KayokoCore_FRAMEWORKS += Security
KayokoCore_FRAMEWORKS += UIKit
KayokoCore_PRIVATE_FRAMEWORKS += CoreServices

KayokoCore_LIBRARIES += sqlite3
ifeq ($(THEOS_DEVICE_SIMULATOR),1)
KayokoCore_LDFLAGS += /opt/simject/CydiaSubstrate.framework/CydiaSubstrate -rpath /opt/simject -Wl,-headerpad_max_install_names
else
KayokoCore_LIBRARIES += substrate
endif
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
KayokoCore_LIBRARIES += roothide
endif

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
include $(THEOS_MAKE_PATH)/tweak.mk
