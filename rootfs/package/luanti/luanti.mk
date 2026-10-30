################################################################################
#
# luanti
#
################################################################################

LUANTI_VERSION = 5.17.0
LUANTI_SITE = $(call github,luanti-org,luanti,$(LUANTI_VERSION))
LUANTI_LICENSE = LGPL-2.1+ (code), CC-BY-SA-3.0 (textures, sounds)
LUANTI_LICENSE_FILES = LICENSE.txt
LUANTI_SUPPORTS_IN_SOURCE_BUILD = NO

LUANTI_DEPENDENCIES = freetype jpeg jsoncpp libgles libpng libvorbis openal \
	sdl2 sqlite zlib zstd

# the Mali-400 only does GLES2; no server, curl (ContentDB) or databases besides sqlite, and no OpenSSL:
# Luanti hashes with its own code otherwise, and libcrypto took ~4 MB of the process
# 5.17.0 with the handheld patches of github.com/alvesmaicon/luanti (tag 5.17.0-handheld.N): the number stays
# 5.17.0 for games' min_minetest_version, the suffix goes up with each binary
LUANTI_CONF_OPTS = \
	-DVERSION_EXTRA=handheld.25 \
	-DBUILD_CLIENT=ON \
	-DBUILD_SERVER=OFF \
	-DBUILD_UNITTESTS=OFF \
	-DBUILD_BENCHMARKS=OFF \
	-DBUILD_DOCUMENTATION=OFF \
	-DRUN_IN_PLACE=OFF \
	-DENABLE_UPDATE_CHECKER=OFF \
	-DENABLE_LTO=OFF \
	-DENABLE_GLES2=ON \
	-DENABLE_OPENGL=OFF \
	-DENABLE_OPENGL3=OFF \
	-DENABLE_SOUND=ON \
	-DENABLE_CURL=OFF \
	-DENABLE_OPENSSL=OFF \
	-DENABLE_CURSES=OFF \
	-DENABLE_POSTGRESQL=OFF \
	-DENABLE_LEVELDB=OFF \
	-DENABLE_REDIS=OFF \
	-DENABLE_SPATIAL=OFF \
	-DENABLE_PROMETHEUS=OFF \
	-DENABLE_SYSTEM_GMP=OFF \
	-DENABLE_SYSTEM_JSONCPP=ON

ifeq ($(BR2_PACKAGE_LUAJIT),y)
LUANTI_DEPENDENCIES += luajit
LUANTI_CONF_OPTS += -DENABLE_LUAJIT=ON -DREQUIRE_LUAJIT=ON
else
LUANTI_CONF_OPTS += -DENABLE_LUAJIT=OFF
endif

ifeq ($(BR2_SYSTEM_ENABLE_NLS),y)
LUANTI_DEPENDENCIES += $(TARGET_NLS_DEPENDENCIES)
LUANTI_CONF_OPTS += -DENABLE_GETTEXT=ON
else
LUANTI_CONF_OPTS += -DENABLE_GETTEXT=OFF
endif

# desktop files are of no use on the console; the launcher wants its icon in /usr/share/icons.
# LICENSE.txt (credits of the CC BY-SA media) would go to /usr/share/doc, which Buildroot drops
define LUANTI_INSTALL_LAUNCHER_ICON
	rm -f $(TARGET_DIR)/usr/share/applications/org.luanti.luanti.desktop \
		$(TARGET_DIR)/usr/share/metainfo/org.luanti.luanti.metainfo.xml \
		$(TARGET_DIR)/usr/share/icons/hicolor/*/apps/luanti.*
	$(INSTALL) -D -m 0644 $(@D)/misc/luanti-xorg-icon-128.png \
		$(TARGET_DIR)/usr/share/icons/luanti.png
	$(INSTALL) -D -m 0644 $(@D)/LICENSE.txt $(TARGET_DIR)/usr/share/luanti/LICENSE.txt
endef
LUANTI_POST_INSTALL_TARGET_HOOKS += LUANTI_INSTALL_LAUNCHER_ICON

$(eval $(cmake-package))
