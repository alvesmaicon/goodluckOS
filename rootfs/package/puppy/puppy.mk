################################################################################
#
# puppy
#
################################################################################

PUPPY_SITE = $(PUPPY_PKGDIR)
PUPPY_SITE_METHOD = local

PUPPY_DEPENDENCIES = alsa-lib sdl2 sdl2_image sdl2_ttf

define PUPPY_BUILD_CMDS
	$(TARGET_CXX) $(TARGET_CXXFLAGS) -std=c++17 \
		-I$(PUPPY_PKGDIR)/../common -I$(@D)/src \
		-o $(@D)/puppy $(@D)/src/*.cpp $(@D)/src/system/*.cpp \
		$(TARGET_LDFLAGS) \
		-lpthread -lSDL2 -lSDL2_image -lSDL2_ttf -lasound
endef

define PUPPY_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/puppy $(TARGET_DIR)/usr/bin/puppy
endef

$(eval $(generic-package))
