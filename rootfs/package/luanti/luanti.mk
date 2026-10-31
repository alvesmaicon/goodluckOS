################################################################################
#
# luanti
#
################################################################################

LUANTI_VERSION = 5.18.0
LUANTI_SITE = $(call github,luanti-org,luanti,$(LUANTI_VERSION))
LUANTI_LICENSE = LGPL-2.1+ (code), CC-BY-SA-3.0 (textures, sounds)
LUANTI_LICENSE_FILES = LICENSE.txt
LUANTI_SUPPORTS_IN_SOURCE_BUILD = NO

LUANTI_DEPENDENCIES = freetype jpeg jsoncpp libgles libpng libvorbis openal \
	sdl2 sqlite zlib zstd

# 5.18 extracts ZIP files with libzip, built here as a static library with zlib only: the engine needs no shared
# library an older image lacks (Update Luanti installs only Luanti's own files) and loads no OpenSSL
LUANTI_LIBZIP_VERSION = 1.11.4
LUANTI_LIBZIP_SOURCE = libzip-$(LUANTI_LIBZIP_VERSION).tar.xz
LUANTI_EXTRA_DOWNLOADS = https://libzip.org/download/$(LUANTI_LIBZIP_SOURCE)
LUANTI_LIBZIP = $(LUANTI_DIR)/libzip

define LUANTI_BUILD_LIBZIP
	mkdir -p $(LUANTI_LIBZIP)/src $(LUANTI_LIBZIP)/build
	$(call suitable-extractor,$(LUANTI_LIBZIP_SOURCE)) $(LUANTI_DL_DIR)/$(LUANTI_LIBZIP_SOURCE) | \
		$(TAR) --strip-components=1 -C $(LUANTI_LIBZIP)/src $(TAR_OPTIONS) -
	cd $(LUANTI_LIBZIP)/build && PATH=$(BR_PATH) $(BR2_CMAKE) ../src \
		-DCMAKE_TOOLCHAIN_FILE="$(HOST_DIR)/share/buildroot/toolchainfile.cmake" \
		-DCMAKE_INSTALL_PREFIX=$(LUANTI_LIBZIP)/install -DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_POSITION_INDEPENDENT_CODE=ON -DBUILD_SHARED_LIBS=OFF \
		-DBUILD_TOOLS=OFF -DBUILD_REGRESS=OFF -DBUILD_OSSFUZZ=OFF -DBUILD_EXAMPLES=OFF -DBUILD_DOC=OFF \
		-DENABLE_COMMONCRYPTO=OFF -DENABLE_GNUTLS=OFF -DENABLE_MBEDTLS=OFF -DENABLE_OPENSSL=OFF \
		-DENABLE_WINDOWS_CRYPTO=OFF -DENABLE_BZIP2=OFF -DENABLE_LZMA=OFF -DENABLE_ZSTD=OFF
	$(TARGET_MAKE_ENV) $(MAKE) -C $(LUANTI_LIBZIP)/build install
endef
LUANTI_PRE_CONFIGURE_HOOKS += LUANTI_BUILD_LIBZIP

# the Mali-400 only does GLES2; no server, curl (ContentDB) or databases besides sqlite, and no OpenSSL:
# Luanti hashes with its own code otherwise, and libcrypto took ~4 MB of the process
# 5.18.0 with the handheld patches of github.com/alvesmaicon/luanti (branch handheld/5.18): the number stays
# 5.18.0 for games' min_minetest_version, the suffix goes up with each binary
LUANTI_CONF_OPTS = \
	-DVERSION_EXTRA=handheld.27 \
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
	-DENABLE_SYSTEM_JSONCPP=ON \
	-DLIBZIP_INCLUDE_DIR=$(LUANTI_LIBZIP)/install/include \
	-DLIBZIP_LIBRARY=$(LUANTI_LIBZIP)/install/lib/libzip.a

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
