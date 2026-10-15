################################################################################
#
# luanti-game
#
################################################################################

# minetest_game has no tag since 5.8.0 (2023); master is the maintained one
LUANTI_GAME_VERSION = c42e4d0c0ff9d27ff7b9b308c3cfc14098dd3a0f
LUANTI_GAME_SITE = $(call github,luanti-org,minetest_game,$(LUANTI_GAME_VERSION))
LUANTI_GAME_LICENSE = LGPL-2.1+ (code), LGPL-2.1 (3d_armor code), MIT (mobs code), CC-BY-SA-3.0, CC-BY-SA-4.0, \
	CC-BY-3.0, CC0-1.0, WTFPL (media)
LUANTI_GAME_LICENSE_FILES = LICENSE.txt

LUANTI_GAME_MOBS_REDO_VERSION = b1be18bc86dbe168dbbe0a515103db73d793e21c
LUANTI_GAME_MOBS_ANIMAL_VERSION = ae709770050bcf01d4e68dff0148ac3b09b34994
LUANTI_GAME_MOBS_MONSTER_VERSION = 01856835595dd9684be1f0e094674867ab76f82a
LUANTI_GAME_STAMINA_VERSION = 4b6988d09e13ed746046735f549d1ef7d6ff0b4b
LUANTI_GAME_3D_ARMOR_VERSION = a4f311cbcf8125b4b83ba884d1d0d12f018021da
# the modpack's mods that need nothing outside minetest_game, without the armor stand and wieldview
LUANTI_GAME_3D_ARMOR_MODS = 3d_armor 3d_armor_sfinv armor_wood armor_cactus armor_bronze \
	armor_steel armor_gold armor_diamond shields
LUANTI_GAME_EXTRA_DOWNLOADS = \
	https://codeberg.org/tenplus1/mobs_redo/archive/$(LUANTI_GAME_MOBS_REDO_VERSION).tar.gz \
	https://codeberg.org/tenplus1/mobs_animal/archive/$(LUANTI_GAME_MOBS_ANIMAL_VERSION).tar.gz \
	https://codeberg.org/tenplus1/mobs_monster/archive/$(LUANTI_GAME_MOBS_MONSTER_VERSION).tar.gz \
	https://codeberg.org/tenplus1/stamina/archive/$(LUANTI_GAME_STAMINA_VERSION).tar.gz \
	https://github.com/minetest-mods/3d_armor/archive/$(LUANTI_GAME_3D_ARMOR_VERSION).tar.gz

# not LUANTI_GAME_DIR: Buildroot owns <pkg>_DIR (the build directory)
LUANTI_GAME_DEST = $(TARGET_DIR)/usr/share/luanti/games/minetest_game

# $(1): mod directory, $(2): the commit whose archive holds it, $(3): more files to leave out;
# screenshot.jpg is a textstudio.com image the game doesn't use (CREDITS.txt)
define LUANTI_GAME_EXTRACT_MOD
	mkdir -p $(LUANTI_GAME_DEST)/mods/$(1)
	$(call suitable-extractor,$(2).tar.gz) $(LUANTI_GAME_DL_DIR)/$(2).tar.gz | \
		$(TAR) --strip-components=1 --exclude=screenshot.jpg $(3) -C $(LUANTI_GAME_DEST)/mods/$(1) $(TAR_OPTIONS) -
endef

# mods inside the game's mods/ are on in every world, with no world.mt to edit
define LUANTI_GAME_INSTALL_TARGET_CMDS
	rm -rf $(LUANTI_GAME_DEST)
	mkdir -p $(LUANTI_GAME_DEST)
	cp -a $(@D)/game.conf $(@D)/minetest.conf $(@D)/settingtypes.txt $(@D)/LICENSE.txt \
		$(@D)/menu $(@D)/mods $(LUANTI_GAME_DEST)/
	# Survival or Creative is asked when the world is made (goodluck_creative): the engine always runs in survival,
	# the menu shows no Creative/Damage checkboxes, and no Host Server (the console has no network)
	echo 'disabled_settings = creative_mode, !enable_damage, enable_server' >> $(LUANTI_GAME_DEST)/game.conf
	# the rat's media has no clear license and is left out, so the rat is off
	echo 'mobs_animal.rat = false' >> $(LUANTI_GAME_DEST)/minetest.conf
	$(call LUANTI_GAME_EXTRACT_MOD,mobs,$(LUANTI_GAME_MOBS_REDO_VERSION))
	$(call LUANTI_GAME_EXTRACT_MOD,mobs_animal,$(LUANTI_GAME_MOBS_ANIMAL_VERSION),--exclude='mobs_rat*' --exclude=mobs_cooked_rat.png)
	$(call LUANTI_GAME_EXTRACT_MOD,mobs_monster,$(LUANTI_GAME_MOBS_MONSTER_VERSION))
	$(call LUANTI_GAME_EXTRACT_MOD,stamina,$(LUANTI_GAME_STAMINA_VERSION),--exclude=stamina_burp.ogg)
	mkdir -p $(LUANTI_GAME_DEST)/mods/3d_armor
	$(call suitable-extractor,$(LUANTI_GAME_3D_ARMOR_VERSION).tar.gz) \
		$(LUANTI_GAME_DL_DIR)/$(LUANTI_GAME_3D_ARMOR_VERSION).tar.gz | \
		$(TAR) --strip-components=1 --exclude='*.blend' -C $(LUANTI_GAME_DEST)/mods/3d_armor \
		$(TAR_OPTIONS) - $(addprefix 3d_armor-$(LUANTI_GAME_3D_ARMOR_VERSION)/,modpack.conf \
		LICENSE.md $(LUANTI_GAME_3D_ARMOR_MODS))
	sed -e 's/@LUANTI_GAME_VERSION@/$(LUANTI_GAME_VERSION)/' \
		-e 's/@MOBS_REDO_VERSION@/$(LUANTI_GAME_MOBS_REDO_VERSION)/' \
		-e 's/@MOBS_ANIMAL_VERSION@/$(LUANTI_GAME_MOBS_ANIMAL_VERSION)/' \
		-e 's/@MOBS_MONSTER_VERSION@/$(LUANTI_GAME_MOBS_MONSTER_VERSION)/' \
		-e 's/@STAMINA_VERSION@/$(LUANTI_GAME_STAMINA_VERSION)/' \
		-e 's/@3D_ARMOR_VERSION@/$(LUANTI_GAME_3D_ARMOR_VERSION)/' \
		-e 's/@3D_ARMOR_MODS@/$(strip $(LUANTI_GAME_3D_ARMOR_MODS))/' \
		$(LUANTI_GAME_PKGDIR)/CREDITS.txt > $(LUANTI_GAME_DEST)/CREDITS.txt
endef

$(eval $(generic-package))
