TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = Island
Island_FILES = Tweak.m
Island_FRAMEWORKS = UIKit QuartzCore
Island_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function

include $(THEOS_MAKE_PATH)/tweak.mk
