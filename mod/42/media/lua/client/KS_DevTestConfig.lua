local KnoxDevTests = rawget(_G, "KnoxDevTests") or {}
_G.KnoxDevTests = KnoxDevTests

-- Development builds run the smallest currently supported scenario automatically.
-- This file never reads or writes Project Zomboid sandbox options.
KnoxDevTests.enabled = true
KnoxDevTests.activeScenario = "movement"
KnoxDevTests.sandboxOverrides = false

KnoxDevTests.scenarios = {
    movement = "ACTIVE",
    equipment = "WAITING_FOR_IMPLEMENTATION",
    combat = "WAITING_FOR_IMPLEMENTATION",
    loot = "WAITING_FOR_IMPLEMENTATION",
    health = "WAITING_FOR_IMPLEMENTATION",
    medical = "WAITING_FOR_IMPLEMENTATION",
    persistence = "WAITING_FOR_IMPLEMENTATION",
}

