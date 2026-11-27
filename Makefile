TARGET := iphone:clang:latest:15.0
ARCHS := arm64

THEOS_PACKAGE_SCHEME := rootless

INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

# Main Dynamic Island Tweak
TWEAK_NAME := RealisticDynamic

RealisticDynamic_FILES := Tweak.xm

RealisticDynamic_FRAMEWORKS := UIKit QuartzCore AVFoundation CallKit

RealisticDynamic_CFLAGS := \
    -fobjc-arc \
    -Wno-deprecated-declarations \
    -Wno-unused-function

RealisticDynamic_LDFLAGS := \
    -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk

# Preferences Bundle
BUNDLE_NAME := RealisticDynamicPrefs

RealisticDynamicPrefs_FILES := RootListController.m

RealisticDynamicPrefs_FRAMEWORKS := UIKit

RealisticDynamicPrefs_INSTALL_PATH := /Library/PreferenceBundles

RealisticDynamicPrefs_CFLAGS := \
    -fobjc-arc

RealisticDynamicPrefs_LDFLAGS := \
    -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk
