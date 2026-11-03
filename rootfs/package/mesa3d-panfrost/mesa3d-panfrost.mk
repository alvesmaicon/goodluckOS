################################################################################
#
# mesa3d-panfrost
#
################################################################################

# Mesa's CL tools from mesa3d's own tarball, as Buildroot's host-mesa3d builds them,
# but against the build machine's LLVM, clang, libclc and SPIR-V libraries
HOST_MESA3D_PANFROST_VERSION = $(MESA3D_VERSION)
HOST_MESA3D_PANFROST_SOURCE = $(MESA3D_SOURCE)
HOST_MESA3D_PANFROST_SITE = $(MESA3D_SITE)
HOST_MESA3D_PANFROST_DL_SUBDIR = mesa3d
HOST_MESA3D_PANFROST_LICENSE = $(MESA3D_LICENSE)
HOST_MESA3D_PANFROST_LICENSE_FILES = $(MESA3D_LICENSE_FILES)

HOST_MESA3D_PANFROST_DEPENDENCIES = \
	host-libdrm \
	host-python-mako \
	host-python-pyyaml

HOST_MESA3D_PANFROST_CONF_ENV = \
	PKG_CONFIG_LIBDIR="$(HOST_DIR)/lib/pkgconfig:$(HOST_DIR)/share/pkgconfig:/usr/lib/$(shell $(HOSTCC) -dumpmachine)/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig"

HOST_MESA3D_PANFROST_CONF_OPTS = \
	-Dglvnd=disabled \
	-Dgallium-drivers=panfrost \
	-Dtools=panfrost \
	-Dinstall-mesa-clc=true \
	-Dllvm=enabled \
	-Dmesa-clc=enabled \
	-Dplatforms= \
	-Dprecomp-compiler=enabled \
	-Dglx=disabled \
	-Dvulkan-drivers=""

define HOST_MESA3D_PANFROST_INSTALL_CMDS
	$(INSTALL) -D -m 0755 $(@D)/buildroot-build/src/compiler/clc/mesa_clc $(HOST_DIR)/bin/mesa_clc
	$(INSTALL) -D -m 0755 $(@D)/buildroot-build/src/compiler/spirv/vtn_bindgen2 $(HOST_DIR)/bin/vtn_bindgen2
	$(INSTALL) -D -m 0755 $(@D)/buildroot-build/src/panfrost/clc/panfrost_compile $(HOST_DIR)/bin/panfrost_compile
endef

$(eval $(host-meson-package))

ifeq ($(BR2_PACKAGE_MESA3D_PANFROST),y)
MESA3D_GALLIUM_DRIVERS-y += panfrost
MESA3D_CONF_OPTS += -Dmesa-clc=system -Dprecomp-compiler=system
# mesa3d.mk was read before this file, so its dependency list is already fixed
$(MESA3D_TARGET_CONFIGURE): | host-mesa3d-panfrost
endif
