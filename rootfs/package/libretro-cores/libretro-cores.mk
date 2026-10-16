################################################################################
#
# libretro-cores
#
################################################################################

LIBRETRO_CORES_VERSION = Latest
LIBRETRO_CORES_SITE = https://github.com/libretro/libretro-super.git
LIBRETRO_CORES_SITE_METHOD = git
LIBRETRO_CORES_LICENSE = Various (GPL-2.0+, MIT, Non-Commercial)
LIBRETRO_CORES_LICENSE_FILES = COPYING

LIBRETRO_CORES_DEPENDENCIES = zlib host-cmake

LIBRETRO_MAJOR_CORES_LIST = \
	fceumm \
	snes9x2005 \
	genesis_plus_gx \
	quicknes \
	dosbox \
	pcsx_rearmed \
	gambatte

CMAKE_LIBRETRO_CORES_LIST = \
	mgba

# core:repo:commit on github.com/libretro, tarball hashes in libretro-cores.hash
LIBRETRO_CORES_COMMITS = \
	fceumm:libretro-fceumm:7a542dab1e87679921962a9f056186eca425c0c2 \
	snes9x2005:snes9x2005:a79dfe9047e7fec58808aefe48ad2bf499c7af11 \
	genesis_plus_gx:Genesis-Plus-GX:393f70cd64c7334564c19a424c383f53986c13f4 \
	quicknes:QuickNES_Core:26bb785c9deddb66a17717b21bb4e328f03ade32 \
	dosbox:dosbox-libretro:a563bb5e9753f207d74e9d8c417d793b784fa4be \
	pcsx_rearmed:pcsx_rearmed:c8816799b50388e61cfe237fe2cdbb7d8175f20a \
	gambatte:gambatte-libretro:d9d6cd06382d1ced30de34d56d3609452323dab1 \
	mgba:mgba:7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6

LIBRETRO_CORES_TARBALL_URL = https://github.com/libretro/$(word 2,$(1))/archive/$(word 3,$(1))/$(word 2,$(1))-$(word 3,$(1)).tar.gz
LIBRETRO_CORES_EXTRA_DOWNLOADS = $(foreach c,$(LIBRETRO_CORES_COMMITS),$(call LIBRETRO_CORES_TARBALL_URL,$(subst :, ,$(c))))

define LIBRETRO_CORES_EXTRACT_CORES
	for c in $(LIBRETRO_CORES_COMMITS); do \
		set -- $$(echo $$c | tr : ' '); \
		mkdir -p $(@D)/libretro-$$1 && \
		$(TAR) xzf $(LIBRETRO_CORES_DL_DIR)/$$2-$$3.tar.gz --strip-components=1 -C $(@D)/libretro-$$1 || exit 1; \
	done
endef
LIBRETRO_CORES_POST_EXTRACT_HOOKS += LIBRETRO_CORES_EXTRACT_CORES

define LIBRETRO_CORES_BUILD_CMDS
	cd $(@D) && \
		CC="$(TARGET_CC)" \
		CXX="$(TARGET_CXX)" \
		AR="$(TARGET_AR)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		CXXFLAGS="$(TARGET_CXXFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		MAKE="$(MAKE)" \
		./libretro-build.sh $(LIBRETRO_MAJOR_CORES_LIST)

	rm -rf $(@D)/libretro-mgba/build
	mkdir -p $(@D)/libretro-mgba/build
	cd $(@D)/libretro-mgba/build && \
		$(HOST_DIR)/bin/cmake .. \
			-DCMAKE_TOOLCHAIN_FILE=$(HOST_DIR)/share/buildroot/toolchainfile.cmake \
			-DCMAKE_BUILD_TYPE=Release \
			-DBUILD_LIBRETRO=ON \
			-DBUILD_SDL=OFF \
			-DBUILD_QT=OFF \
			-DUSE_FFMPEG=OFF \
			-DUSE_SQLITE3=OFF \
			-DUSE_MINIZIP=OFF \
			-DUSE_EDITLINE=OFF \
			-DUSE_DISCORD_RPC=OFF
	$(MAKE) -C $(@D)/libretro-mgba/build mgba_libretro

	mkdir -p $(@D)/dist/unix
	cp $(@D)/libretro-mgba/build/mgba_libretro.so $(@D)/dist/unix/mgba_libretro.so
endef

define LIBRETRO_CORES_INSTALL_TARGET_CMDS
	$(INSTALL) -d $(TARGET_DIR)/usr/lib/libretro
	find $(@D)/dist/unix -name "*_libretro.so" -exec \
		$(INSTALL) -D -m 0755 {} $(TARGET_DIR)/usr/lib/libretro/ \;
endef

$(eval $(generic-package))
