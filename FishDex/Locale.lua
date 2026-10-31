-- Strings shown to the player. enUS is the base; frFR overrides every key (a parity test
-- keeps the two lists equal). Item, zone and recipe names come from the game, not from here.
local _, ns = ...

local L = {}
ns.L = L

local enUS = {
    TITLE = "FishDex",
    CAT_fish = "Fish",
    CAT_rare = "Rare",
    CAT_trophy = "Trophies",
    CAT_wreck = "Wrecks",
    CAT_item = "Items",
    CAT_found = "Discoveries",
    PROGRESS = "%d / %d caught",
    TOTAL = "Total: %d / %d",
    UNKNOWN_NAME = "???",
    NOT_CAUGHT = "Not caught yet",
    WHERE = "Where to fish it",
    NO_ZONE = "Unknown (fished on this account)",
    RECIPES = "Recipes",
    NO_RECIPE = "No recipe uses it",
    KNOWN = "known",
    UNKNOWN_RECIPE = "not learned",
    UNSCANNED = "unchecked",
    PROF_cooking = "Cooking",
    PROF_alchemy = "Alchemy",
    CAUGHT_COUNT = "Caught %d times",
    FIRST_CATCH = "First catch: %s",
    FIRST_ZONE = "in %s",
    NEW_CATCH = "New catch: %s!",
    OPT_SOUND = "Sound",
    OPT_ANNOUNCE = "Announce",
    SELECT_HINT = "Select an entry to see its details.",
    HELP = "/fishdex: open the window. /fishdex sound: sound on or off. /fishdex announce: announce on or off.",
    SOUND_ON = "new catch sound on",
    SOUND_OFF = "new catch sound off",
    ANNOUNCE_ON = "new catch announce on",
    ANNOUNCE_OFF = "new catch announce off",
}

local frFR = {
    TITLE = "FishDex",
    CAT_fish = "Poissons",
    CAT_rare = "Rares",
    CAT_trophy = "Trophées",
    CAT_wreck = "Épaves",
    CAT_item = "Objets",
    CAT_found = "Découvertes",
    PROGRESS = "%d / %d capturés",
    TOTAL = "Total : %d / %d",
    UNKNOWN_NAME = "???",
    NOT_CAUGHT = "Pas encore capturé",
    WHERE = "Où le pêcher",
    NO_ZONE = "Inconnu (pêché sur ce compte)",
    RECIPES = "Recettes",
    NO_RECIPE = "Aucune recette ne l'utilise",
    KNOWN = "connue",
    UNKNOWN_RECIPE = "pas apprise",
    UNSCANNED = "non vérifiée",
    PROF_cooking = "Cuisine",
    PROF_alchemy = "Alchimie",
    CAUGHT_COUNT = "Capturé %d fois",
    FIRST_CATCH = "Première capture : %s",
    FIRST_ZONE = "à %s",
    NEW_CATCH = "Nouvelle prise : %s !",
    OPT_SOUND = "Son",
    OPT_ANNOUNCE = "Annonce",
    SELECT_HINT = "Choisis une entrée pour voir ses détails.",
    HELP = "/fishdex : ouvre la fenêtre. /fishdex son : son activé ou non. /fishdex annonce : annonce activée ou non.",
    SOUND_ON = "son des nouvelles prises activé",
    SOUND_OFF = "son des nouvelles prises désactivé",
    ANNOUNCE_ON = "annonce des nouvelles prises activée",
    ANNOUNCE_OFF = "annonce des nouvelles prises désactivée",
}

ns.LOCALES = { enUS = enUS, frFR = frFR }

-- Fills L for `locale` (enUS for any language without its own table).
function ns.setLocale(locale)
    local chosen = ns.LOCALES[locale] or enUS
    for k in pairs(L) do L[k] = nil end
    for k, v in pairs(enUS) do L[k] = chosen[k] or v end
end

ns.setLocale(type(GetLocale) == "function" and GetLocale() or "enUS")
