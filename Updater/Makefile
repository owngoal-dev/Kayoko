ifneq ($(THEOS_DEVICE_SIMULATOR),1)
ARCHS := arm64
endif
TOOL_NAME := kayoko_updater

kayoko_updater_USE_MODULES := 0

kayoko_updater_FILES += main.m
kayoko_updater_FILES += KayokoCopyLogImporter.m
kayoko_updater_FILES += KayokoCopyVaultImporter.m
kayoko_updater_FILES += KayokoImportFileStager.m
kayoko_updater_FILES += KayokoPostinstallUpdater.m
kayoko_updater_FILES += ../Tweak/Core/Manager/KayokoHistoryStore.m
kayoko_updater_FILES += ../Tweak/Core/Manager/KayokoHistoryMigrator.m
kayoko_updater_FILES += ../Tweak/Core/Manager/KayokoPasteboardItem.m
kayoko_updater_FILES += ../Tweak/Core/Manager/KayokoRichTextRepresentation.m
kayoko_updater_FILES += ../Tweak/Core/Manager/KayokoSearchCriteria.m
kayoko_updater_FILES += ../Shared/Tags/KayokoTag.m
kayoko_updater_FILES += ../Shared/Tags/KayokoTagStore.m
kayoko_updater_FILES += ../Shared/Purchases/KayokoPurchaseAuthorization.m

kayoko_updater_CFLAGS += -fobjc-arc
kayoko_updater_CFLAGS += -I../Tweak/Core/Manager
kayoko_updater_CFLAGS += -I../Preferences
kayoko_updater_CFLAGS += -I../Shared/Tags
kayoko_updater_CFLAGS += -I../Shared/Purchases
kayoko_updater_CFLAGS += -I../Shared

kayoko_updater_FRAMEWORKS += CoreGraphics
kayoko_updater_FRAMEWORKS += ImageIO
kayoko_updater_FRAMEWORKS += Security
kayoko_updater_FRAMEWORKS += UIKit
kayoko_updater_LIBRARIES += sqlite3
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
kayoko_updater_LIBRARIES += roothide
endif

kayoko_updater_INSTALL_PATH := /usr/local/libexec
ifneq ($(THEOS_DEVICE_SIMULATOR),1)
kayoko_updater_CODESIGN_FLAGS += -Splatformize.entitlements
endif

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/tool.mk
