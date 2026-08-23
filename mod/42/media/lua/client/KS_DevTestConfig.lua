local KnoxDevTests = rawget(_G, "KnoxDevTests") or {}
_G.KnoxDevTests = KnoxDevTests

-- Development builds run one narrow automated gate at a time.
-- This file never reads or writes Project Zomboid sandbox options.
KnoxDevTests.enabled = true
KnoxDevTests.activeScenario = "combat"
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
    combat = "ACTIVE",
    loot = "WAITING_FOR_IMPLEMENTATION",
    health = "WAITING_FOR_IMPLEMENTATION",
    medical = "WAITING_FOR_IMPLEMENTATION",
    persistence = "PARTIAL_IN_EQUIPMENT_GATE",
}
