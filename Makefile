TARGET := iphone:clang:latest:15.0
ARCHS := arm64

THEOS_PACKAGE_SCHEME := rootless

INSTALL_TARGET_PROCESSES := SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME := RealisticDynamic

RealisticDynamic_FILES := Tweak.m

RealisticDynamic_FRAMEWORKS := UIKit QuartzCore

RealisticDynamic_CFLAGS := \
    -fobjc-arc \
    -Wno-deprecated-declarations \
    -Wno-unused-function

RealisticDynamic_LDFLAGS := \
    -Wl,-undefined,dynamic_lookup

include $(THEOS_MAKE_PATH)/tweak.mk
