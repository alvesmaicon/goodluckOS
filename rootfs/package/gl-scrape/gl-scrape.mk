################################################################################
#
# gl-scrape
#
################################################################################

GL_SCRAPE_SITE = $(GL_SCRAPE_PKGDIR)
GL_SCRAPE_SITE_METHOD = local

# SS_DEVID and SS_DEVPASSWORD come from the environment (a CI secret, dev/gl's .env)
define GL_SCRAPE_BUILD_CMDS
	$(GL_SCRAPE_PKGDIR)/credentials.sh > $(@D)/src/credentials.h
	$(TARGET_CXX) $(TARGET_CXXFLAGS) -std=c++17 -I$(@D)/src \
		-o $(@D)/gl-scrape $(@D)/src/*.cpp $(TARGET_LDFLAGS)
endef

define GL_SCRAPE_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/gl-scrape $(TARGET_DIR)/usr/bin/gl-scrape
endef

$(eval $(generic-package))
