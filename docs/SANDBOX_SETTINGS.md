# Sandbox settings

Knox Survivors adds two pages to Project Zomboid's sandbox options.

## Knox Survivors

- **Enable Knox Survivors** pauses the rebuild's gameplay entry points without deleting survivor save data.
- **World Population** sets the persistent starting population and, normally, the living-survivor target across the map. The default is 32 and the supported range is 0–256.
- **Disable Survivor Caps** is off by default. When enabled, the active-survivor and companion counts do not block activation or recruitment. World Population remains the starting count, but later arrivals may exceed it: at most one new identity per refill interval at an unused world location. Trust, ownership, death, safe spawning and cooldown rules still apply. There is no separate numeric faction cap to bypass. Larger active populations can reduce performance.
- **Max Active Survivors** normally caps how many production survivors may be physically materialized at once. The default is 12 and the supported range is 1–48. Disabling caps ignores this setting; the scheduler still builds at most two new bodies per population update instead of loading a whole settlement in one burst. This rate limit does not impose a total-body cap.
- **Population Refill Days** controls how long a population deficit must persist before one replacement identity is allocated. Refill is gradual, never a catch-up burst.
- **Minimum Spawn Distance** keeps first materialization away from local players and out of immediate view. Saved survivors always restore at their exact recorded square once it is loaded.
- **Companion Limit** controls how many active companions each local player may recruit.
- **Allow NPC Factions** controls new faction formation and base scouting. Existing factions remain intact.
- **Allow Hostile Survivor Encounters** controls threats and robberies between independent survivors.
- **Show Companion HUD** controls the right-side companion panel.
- **Show Survivor Activity Feed** controls the Knox message window. Speech bubbles still work.

Production population uses real Build 42 player starts and supplemental ground-floor building locations. Distant survivors retain virtual locations and nearby loaded survivors materialize only when safe. Dead origins remain reserved. Disabling caps never recycles dead identities or repeatedly spawns a batch after a long time skip. Re-enabling caps does not delete existing survivors or forcibly dismiss companions. With caps disabled, a starting population of zero can still receive later gradual arrivals.

## Developer tools

Developer tools are disabled by default. Enable **Knox Survivors - Developer Tools > Enable Developer Tools** before creating or loading the test save.

The automatic scenario can load one survivor, one companion, a two-person travel group, a three-person faction, or a faction that immediately starts using the normal base-scouting behavior. Leave it on **None** to spawn scenarios manually.

With developer tools enabled, right-click the world and open **Knox Survivors - Developer Tools**. The menu separates persistent survivor-population presets from one-click combat presets. Combat presets cover survivor, travel-group, faction, and stress-test fights; they report results automatically and can write a detailed combat snapshot to `console.txt`. Cleanup removes only zombies created by the active combat preset.

Every test survivor receives an isolated, save-persistent `ks-dev-*` identity. Each automatic scenario keeps its own identities, so changing scenarios cannot accidentally recruit or regroup somebody left over from a different test. Spawning a scenario is therefore a real persistence test, not a disposable visual prop. Destructive tests remain behind their own off-by-default option.
