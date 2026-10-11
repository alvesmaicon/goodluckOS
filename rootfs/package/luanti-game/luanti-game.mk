################################################################################
#
# luanti-game
#
################################################################################

# minetest_game has no tag since 5.8.0 (2023); master is the maintained one
LUANTI_GAME_VERSION = c42e4d0c0ff9d27ff7b9b308c3cfc14098dd3a0f
LUANTI_GAME_SITE = $(call github,luanti-org,minetest_game,$(LUANTI_GAME_VERSION))
LUANTI_GAME_LICENSE = LGPL-2.1+ (code), CC-BY-SA-3.0 (media), MIT (mobs code)
LUANTI_GAME_LICENSE_FILES = LICENSE.txt

LUANTI_GAME_MOBS_REDO_VERSION = b1be18bc86dbe168dbbe0a515103db73d793e21c
LUANTI_GAME_MOBS_ANIMAL_VERSION = ae709770050bcf01d4e68dff0148ac3b09b34994
LUANTI_GAME_EXTRA_DOWNLOADS = \
	https://codeberg.org/tenplus1/mobs_redo/archive/$(LUANTI_GAME_MOBS_REDO_VERSION).tar.gz \
	https://codeberg.org/tenplus1/mobs_animal/archive/$(LUANTI_GAME_MOBS_ANIMAL_VERSION).tar.gz

LUANTI_GAME_DIR = $(TARGET_DIR)/usr/share/luanti/games/minetest_game

# mods inside the game's mods/ are on in every world, with no world.mt to edit
define LUANTI_GAME_INSTALL_TARGET_CMDS
	rm -rf $(LUANTI_GAME_DIR)
	mkdir -p $(LUANTI_GAME_DIR)
	cp -a $(@D)/game.conf $(@D)/minetest.conf $(@D)/settingtypes.txt $(@D)/LICENSE.txt \
		$(@D)/menu $(@D)/mods $(LUANTI_GAME_DIR)/
	mkdir -p $(LUANTI_GAME_DIR)/mods/mobs $(LUANTI_GAME_DIR)/mods/mobs_animal
	$(call suitable-extractor,$(LUANTI_GAME_MOBS_REDO_VERSION).tar.gz) \
		$(LUANTI_GAME_DL_DIR)/$(LUANTI_GAME_MOBS_REDO_VERSION).tar.gz | \
		$(TAR) --strip-components=1 -C $(LUANTI_GAME_DIR)/mods/mobs $(TAR_OPTIONS) -
	$(call suitable-extractor,$(LUANTI_GAME_MOBS_ANIMAL_VERSION).tar.gz) \
		$(LUANTI_GAME_DL_DIR)/$(LUANTI_GAME_MOBS_ANIMAL_VERSION).tar.gz | \
		$(TAR) --strip-components=1 -C $(LUANTI_GAME_DIR)/mods/mobs_animal $(TAR_OPTIONS) -
endef

$(eval $(generic-package))
