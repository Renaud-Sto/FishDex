-- A hand-picked selection of the game's own sound files (fanfares, bells, jingles,
-- achievement and loot sounds) the game gives no name to. File ids come from the
-- community listfile (wowdev/wow-listfile, 2026-10-31); the path is in the comment.
-- Ids under 1,000,000 are Classic-era files, the likeliest to exist on Forever.
local _, ns = ...

ns.SoundList = {
    GROUPS = { "success", "fanfare", "loot", "bell", "fishing" },
    -- { file id, English name, French name, group }
    { 569143, "Achievement", "Haut fait", "success" }, -- sound/spells/achievmentsound1
    { 567431, "Level up", "Niveau supérieur", "success" }, -- sound/interface/levelup
    { 567478, "Level up 2", "Niveau supérieur 2", "success" }, -- levelup2
    { 567528, "Guild level up", "Niveau de guilde", "success" }, -- ui_guildlevelup
    { 642845, "Profession skill up", "Progression de métier", "success" }, -- ui_tradeskill_levelup_01
    { 642841, "Pet level up", "Niveau de mascotte", "success" }, -- ui_pet_levelup_01
    { 567439, "Quest complete", "Quête terminée", "success" }, -- iquestcomplete
    { 567476, "Quest complete 2", "Quête terminée 2", "success" }, -- autoquestcomplete
    { 642843, "Objective complete", "Objectif accompli", "success" }, -- ui_quest_objectivecomplete_01
    { 1489470, "World quest complete", "Expédition terminée", "success" }, -- ui_worldquest_complete
    { 876092, "Bonus objective", "Objectif bonus", "success" }, -- ui_scenario_bonusobjective_success
    { 903976, "Trial success", "Épreuve réussie", "success" }, -- ui_provinggrounds_trial_success

    { 567408, "PvP victory (Alliance)", "Victoire JcJ (Alliance)", "fanfare" }, -- pvpvictoryalliancemono
    { 567495, "PvP victory (Horde)", "Victoire JcJ (Horde)", "fanfare" }, -- pvpvictoryhordemono
    { 648423, "Pet battle victory", "Victoire de mascotte", "fanfare" }, -- ui_petbattle_victory01
    { 658420, "Pet battle victory 2", "Victoire de mascotte 2", "fanfare" }, -- ui_petbattle_victory02
    { 644933, "Victory fanfare (human)", "Fanfare de victoire (humain)", "fanfare" }, -- mus_pb_w2_humanvictory
    { 644935, "Victory fanfare (orc)", "Fanfare de victoire (orc)", "fanfare" }, -- mus_pb_w2_orcvictory
    { 775180, "Brawl won (Alliance)", "Bagarre gagnée (Alliance)", "fanfare" }, -- ui_51_brawlersguild_victory_alliance
    { 775184, "Brawl won (Horde)", "Bagarre gagnée (Horde)", "fanfare" }, -- ui_51_brawlersguild_victory_horde
    { 653742, "Serpent riders victory", "Victoire des cavaliers", "fanfare" }, -- mus_50_serpentriders_victory_stinger
    { 1067170, "Mission success", "Mission réussie", "fanfare" }, -- ui_garrison_commandtable_missionsuccess_stinger
    { 1054629, "Mission success 2", "Mission réussie 2", "fanfare" }, -- ui_garrison_mission_complete_mission_success
    { 371379, "Event stinger", "Jingle d'événement", "fanfare" }, -- music/event/zfstinger10
    { 371380, "Event stinger 2", "Jingle d'événement 2", "fanfare" }, -- zfstinger11
    { 229973, "Dungeon end stinger", "Fin de donjon", "fanfare" }, -- ct_stratholmepastendstinger

    { 642829, "Epic loot", "Butin épique", "loot" }, -- ui_epicloot_toast_01
    { 1489461, "Legendary item", "Objet légendaire", "loot" }, -- ui_legendary_item_toast
    { 1138111, "Loot won", "Butin gagné", "loot" }, -- ui_loot_toast_lesser_item_won_01
    { 1130983, "Raid loot banner", "Bannière de butin", "loot" }, -- ui_raid_loot_banner_01
    { 642823, "Bonus roll", "Jet bonus", "loot" }, -- ui_bonuslootroll_end_01
    { 899283, "Dig site complete", "Fouille terminée", "loot" }, -- ui_digsitecompletiontoast
    { 441791, "Treasure jingle", "Jingle de trésor", "loot" }, -- music/cataclysm/mus_treasure_uu01
    { 441792, "Treasure jingle 2", "Jingle de trésor 2", "loot" }, -- mus_treasure_uu02
    { 441793, "Treasure jingle 3", "Jingle de trésor 3", "loot" }, -- mus_treasure_uu03
    { 567413, "Coins", "Pièces", "loot" }, -- lootcoinlarge
    { 1067169, "Chest unlocked", "Coffre ouvert", "loot" }, -- ui_garrison_commandtable_chestunlock
    { 4906957, "Purchase celebration", "Achat célébré", "loot" }, -- ui_tradingpost_purchasecelebration_01
    { 4906961, "Purchase celebration 2", "Achat célébré 2", "loot" }, -- ui_tradingpost_purchasecelebration_03
    { 1237429, "Warforged item", "Objet forgé pour la guerre", "loot" }, -- ui_warforged_item_toast_banner

    { 566564, "Bell toll (Alliance)", "Cloche (Alliance)", "bell" }, -- doodad/belltollalliance
    { 565853, "Bell toll (Horde)", "Cloche (Horde)", "bell" }, -- belltollhorde
    { 566558, "Bell toll (night elf)", "Cloche (elfe de la nuit)", "bell" }, -- belltollnightelf
    { 566027, "Tribal drum toll", "Tambour tribal", "bell" }, -- belltolltribal
    { 566254, "Karazhan bell", "Cloche de Karazhan", "bell" }, -- kharazahnbelltoll
    { 565564, "Troll gong", "Gong troll", "bell" }, -- g_gongtroll01
    { 644239, "Titan gong", "Gong titanesque", "bell" }, -- go_mogu_titangong
    { 623894, "Bell and gong", "Cloche et gong", "bell" }, -- wow_mop_intro_sfx_bell_wgong
    { 669386, "Divine bell", "Cloche divine", "bell" }, -- go_pa_divinebell_ring_pure
    { 1100031, "Darkmoon Faire bell", "Cloche de Sombrelune", "bell" }, -- fx_darkmoonfaire_bell
    { 1129273, "Ship bell", "Cloche de navire", "bell" }, -- fx_ship_bell_chime_01
    { 1129275, "Ship bell 2", "Cloche de navire 2", "bell" }, -- fx_ship_bell_chime_03
    { 1514318, "Chime", "Carillon", "bell" }, -- fx_chimesingle_01
    { 1514311, "Wind chimes", "Carillon à vent", "bell" }, -- fx_chimemult_01

    { 569285, "Bobber splash", "Plouf du bouchon", "fishing" }, -- spells/fishingbobber_ver2_1
    { 568970, "Bobber splash 2", "Plouf du bouchon 2", "fishing" }, -- fishingbobber_ver2_2
}
