export PACKAGE_VERSION := 4.3.3

ifeq ($(THEOS_DEVICE_SIMULATOR),1)
export ARCHS := arm64 x86_64
export TARGET := simulator:clang:latest:15.0
export TARGET_CODESIGN_FLAGS := --sign - --force
else
export ARCHS := arm64 arm64e
export TARGET := iphone:clang:16.5:14.0
export INSTALL_TARGET_PROCESSES := backboardd druid pasted
endif

SUBPROJECTS += Tweak/Core
SUBPROJECTS += Tweak/Helper
SUBPROJECTS += Preferences
SUBPROJECTS += Updater

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/aggregate.mk

export THEOS_OBJ_DIR

.PHONY: sim-install

sim-install: all
	@devkit/sim-install.sh
