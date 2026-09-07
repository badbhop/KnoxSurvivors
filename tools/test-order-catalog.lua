local rootPath = arg[1] or "."
package.path = rootPath .. "/mod/42/media/lua/client/?.lua;" .. package.path
require "KS_OrderCatalog"
assert(KnoxOrderCatalog.label("follow") == "Follow")
assert(KnoxOrderCatalog.label("loot_area") == "Explore and Search")
assert(KnoxOrderCatalog.label("rest") == "Rest / Recover")
assert(KnoxOrderCatalog.label("return_to_base") == "Return to Base")
assert(KnoxOrderCatalog.normalize("explore") == "loot_area")
assert(KnoxOrderCatalog.normalize("search") == "loot_area")
assert(KnoxOrderCatalog.normalize("escort") == "follow")
assert(KnoxOrderCatalog.normalize("return_home") == "return_to_base")
assert(KnoxOrderCatalog.normalize("hold_position") == "hold")
assert(KnoxOrderCatalog.normalize("recover") == "relax")
assert(KnoxOrderCatalog.normalize("Go Find Food") == "find_food",
    "human-facing search labels must use the canonical directive")
assert(KnoxOrderCatalog.normalize("Return To Base") == "return_to_base",
    "human-facing return labels must use the canonical primary order")
assert(KnoxOrderCatalog.normalize("Hold Still") == "hold",
    "legacy hold labels must use the canonical primary order")
assert(KnoxOrderCatalog.normalize("Relax and Recover") == "relax",
    "catalogue labels must round-trip to their canonical order")
assert(KnoxOrderCatalog.normalizeTaskType("Farm Water") == "farm_water",
    "task labels must normalize before task-board lookup")
assert(KnoxOrderCatalog.normalize("search_building") == "loot_building")
assert(KnoxOrderCatalog.normalize("chop_wood") == "woodwork")
assert(KnoxOrderCatalog.normalize("pile_corpses") == "hauling")
assert(KnoxOrderCatalog.normalize("loot_dead_bodies") == "loot_corpses")
assert(KnoxOrderCatalog.normalize("get_meds") == "find_medical")
assert(KnoxOrderCatalog.normalize("guard_area") == "guard")
assert(KnoxOrderCatalog.normalize("patrol") == "patrol")
assert(KnoxOrderCatalog.normalizeBasePreference("patrol_area") == "patrol",
    "legacy patrol-area preferences must migrate to the base patrol role")
assert(KnoxOrderCatalog.normalize("cancel") == "resume_normal_duty")
assert(KnoxOrderCatalog.label("explore") == KnoxOrderCatalog.label("loot_area"))
assert(KnoxOrderCatalog.normalize("stop") == "resume_normal_duty")
assert(KnoxOrderCatalog.normalize("barricade") == "woodwork")
assert(KnoxOrderCatalog.normalizeTaskType("haul") == "haul_corpse",
    "legacy haul tasks must converge on the existing depot executor")
assert(KnoxOrderCatalog.normalizeTaskType("patrol_area") == "patrol",
    "legacy patrol-area tasks must converge on the recurring patrol executor")
local persistenceFile = assert(io.open(rootPath .. "/mod/42/media/lua/client/KS_Persistence.lua", "r"))
local persistenceText = persistenceFile:read("*a")
persistenceFile:close()
assert(persistenceText:find("haul = \"haul_corpse\"", 1, true),
    "persistence fallback must normalize haul before the catalogue loads")
assert(persistenceText:find("patrol_area = \"patrol\"", 1, true),
    "persistence fallback must normalize patrol-area tasks before the catalogue loads")
assert(persistenceText:find("LEGACY_ORDER_ALIASES", 1, true)
    and persistenceText:find('survivor.duty.mode == "companion"', 1, true)
    and persistenceText:find('normalizedOrder == "hold"', 1, true),
    "persistence must normalize legacy companion orders before controller restore")
assert(persistenceText:find("return_home = \"return_to_base\"", 1, true)
    and persistenceText:find("recover = \"relax\"", 1, true),
    "persistence fallback must cover legacy return and recovery orders")
assert(persistenceText:find("search_building = \"loot_building\"", 1, true)
    and persistenceText:find("sort_loot_into_base = \"clean_inventory\"", 1, true),
    "persistence fallback must cover legacy search and inventory orders")
assert(persistenceText:find("loot_dead_bodies = \"loot_corpses\"", 1, true)
    and persistenceText:find("cancel = \"resume_normal_duty\"", 1, true),
    "persistence fallback must cover familiar body-loot and cancel orders")
assert(persistenceText:find("directive.kind = canonicalOrder", 1, true),
    "persisted directive aliases must converge before validation")
assert(KnoxOrderCatalog.preferenceMatchesTask("barricade", "barricade"))
local aliasDirective = assert(KnoxOrderCatalog.makeDirective("go_find_food", { minX = 1, minY = 2, z = 0 }))
assert(aliasDirective.kind == "find_food")
assert(KnoxOrderCatalog.label("resume_normal_duty") == "Resume Normal Duty")
assert(KnoxOrderCatalog.label("farm_water") == "Water Crops")
assert(KnoxOrderCatalog.label("construct_defense") == "Build Defenses")
assert(KnoxOrderCatalog.label("unknown_task", "Fallback") == "Fallback")
assert(KnoxOrderCatalog.isDirective("patrol_area"))
assert(not KnoxOrderCatalog.isDirective("patrol"),
    "payload-less patrol must remain a base preference")
assert(not KnoxOrderCatalog.isDirective("follow"))
assert(KnoxOrderCatalog.isPrimaryOrder("follow"))
assert(not KnoxOrderCatalog.isPrimaryOrder("loot_area"))
assert(KnoxOrderCatalog.isBasePreference("farming"))
assert(#KnoxOrderCatalog.basePreferenceOrder == 9
    and KnoxOrderCatalog.basePreferenceOrder[1] == "auto"
    and KnoxOrderCatalog.basePreferenceOrder[9] == "rest",
    "base preference menu order must remain canonical")
assert(KnoxOrderCatalog.isKnown("find_food"))
assert(not KnoxOrderCatalog.isKnown("not_a_knox_order"))
assert(KnoxOrderCatalog.get(nil) == nil and KnoxOrderCatalog.get({}) == nil,
    "invalid order keys fail closed without table-index errors")
local made = assert(KnoxOrderCatalog.makeDirective("find_food", { minX = 1, minY = 2 }))
assert(made.kind == "find_food" and made.minX == 1 and made.minY == 2,
    "catalogue must normalize directive payloads")
assert(KnoxOrderCatalog.makeDirective("not_a_knox_order", {}) == nil,
    "unknown directive construction must fail closed")
local patrolDirective = assert(KnoxOrderCatalog.makeDirective("patrol", { minX = 1, minY = 2 }))
assert(patrolDirective.kind == "patrol_area",
    "payload-bearing patrol shorthand must build the companion patrol directive")
assert(KnoxOrderCatalog.preferenceMatchesTask("farming", "farm_water"))
assert(KnoxOrderCatalog.preferenceMatchesTask("woodwork", "construct_defense"))
assert(KnoxOrderCatalog.preferenceMatchesTask("hauling", "haul_corpse"))
assert(KnoxOrderCatalog.label("barricade") == "Barricade",
    "exact task labels must win over broad legacy aliases")
assert(not KnoxOrderCatalog.preferenceMatchesTask("guard", "farm_seed"))
assert(KnoxOrderCatalog.preferenceForTask("animal_feed") == "animal_care")
assert(KnoxOrderCatalog.preferenceForTask("farm_seed") == "farming")
assert(KnoxOrderCatalog.preferenceForTask("storage_sorting") == nil,
    "legacy task labels must map through the catalogue itself")
assert(not KnoxOrderCatalog.preferenceMatchesTask("hauling", "storage_sorting"),
    "preference matching must normalize legacy task labels at the public boundary")
assert(KnoxOrderCatalog.preferenceMatchesTask("patrol_area", "patrol"),
    "legacy patrol-area resident preferences must match canonical patrol tasks")
assert(KnoxOrderCatalog.label("party_orders") == "Party Orders")
assert(KnoxOrderCatalog.label("move_party") == "Move Party Here")
assert(KnoxOrderCatalog.get("missing") == nil)
local resolvedFollow = assert(KnoxOrderCatalog.resolve("escort"))
assert(resolvedFollow.kind == "follow" and resolvedFollow.category == "primary",
    "legacy follow aliases must resolve through one canonical category")
local resolvedTask = assert(KnoxOrderCatalog.resolve("farm_water"))
assert(resolvedTask.category == "task_preference" and resolvedTask.preference == "farming",
    "concrete settlement tasks must resolve to their existing preference owner")
local resolvedDirective = assert(KnoxOrderCatalog.resolve("search_building"))
assert(resolvedDirective.kind == "loot_building" and resolvedDirective.category == "directive",
    "legacy search labels must resolve to the existing directive executor")
local unknown, unknownResult = KnoxOrderCatalog.resolve("not_a_knox_order")
assert(unknown == nil and unknownResult == "unknown_order",
    "unknown orders must fail closed at the catalogue boundary")
print("Order catalogue PASS labels=true routing=true preferences=true unknown-safe=true")
