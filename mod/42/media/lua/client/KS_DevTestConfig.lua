local KnoxDevTests = rawget(_G, "KnoxDevTests") or {}
_G.KnoxDevTests = KnoxDevTests

-- Development builds run one narrow automated gate at a time.
-- This file never reads or writes Project Zomboid sandbox options.
KnoxDevTests.enabled = true
KnoxDevTests.activeScenario = "survival"
KnoxDevTests.sandboxOverrides = false
KnoxDevTests.obstacleScanRadius = 12
-- A locked-window test permanently smashes one nearby window in the loaded save.
KnoxDevTests.allowDestructiveWindowTest = true
-- The current persistence gate always includes a bag so the back slot is regression-tested.
KnoxDevTests.forceStarterBag = true

KnoxDevTests.scenarios = {
    movement = "ACTIVE_IN_OBSTACLE_SUITE",
    door = "ACTIVE_IN_OBSTACLE_SUITE",
    window_open = "ACTIVE_IN_OBSTACLE_SUITE",
    window_locked = "ACTIVE_DESTRUCTIVE_IN_OBSTACLE_SUITE",
    fence = "ACTIVE_IN_OBSTACLE_SUITE",
    locked_entry = "WAITING_FOR_ALTERNATE_ROUTE_PLANNER",
    equipment = "LIVE_PASS_HIBERNATING",
    combat = "LIVE_PASS_HIBERNATING",
    loot = "LIVE_PASS_HIBERNATING",
    health = "LIVE_PASS_HIBERNATING",
    medical = "LIVE_PASS_RELOAD_VERIFIED_BY_NEEDS_PREFLIGHT",
    medical_supplies = "IMPLEMENTED_DORMANT_AFTER_MEDICAL_RELOAD",
    needs = "LIVE_PASS_HIBERNATING",
    autonomy = "REPLACED_BY_MULTI_SURVIVOR_AUTONOMY",
    persistence = "ACTIVE_ACROSS_APPEARANCE_INVENTORY_HEALTH_NEEDS_POPULATION",
    population = "LIVE_PASS_TWO_SURVIVOR_RUNTIME_HIBERNATING",
    survival = "ACTIVE_MULTI_SURVIVOR_NEEDS_LOOT_COMBAT_ROAM",
    relationships = "ACTIVE_GREETING_TRAVEL_GROUP_FACTION_AT_THREE",
}
