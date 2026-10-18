################################################################################
#
# glos-setup
#
################################################################################

GLOS_SETUP_SITE = $(GLOS_SETUP_PKGDIR)
GLOS_SETUP_SITE_METHOD = local
GLOS_SETUP_DEPENDENCIES = sdl2 imgui

define GLOS_SETUP_BUILD_CMDS
	$(TARGET_CXX) $(TARGET_CXXFLAGS) -std=c++17 \
		-I$(STAGING_DIR)/usr/include/SDL2 \
		-o $(@D)/glos-setup $(@D)/glos-setup.cpp \
		$(TARGET_LDFLAGS) \
		-lpthread -ldrm -lSDL2 -lSDL2_image -lGLESv2 -lEGL -limgui
endef

define GLOS_SETUP_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/glos-setup $(TARGET_DIR)/usr/bin/glos-setup
endef

$(eval $(generic-package))
