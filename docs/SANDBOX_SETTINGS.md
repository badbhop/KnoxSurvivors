# Sandbox settings

Knox Survivors adds two pages to Project Zomboid's sandbox options.

## Knox Survivors

- **Enable Knox Survivors** pauses the rebuild's gameplay entry points without deleting survivor save data.
- **World Population** sets the persistent starting population and, normally, the living-survivor target across the entire map. The balanced playtest default is 48 and the supported range is 0–256.
- **Disable Survivor Caps** is off by default. When enabled, the active-survivor and companion counts do not block activation or recruitment. World Population remains the starting count, but later arrivals may exceed it: at most one new identity per refill interval at an unused world location. Ownership, death, safe spawning, hostility, and group/faction rules still apply. The separate NPC faction-size limit remains in force so one faction cannot grow without bound. Larger active populations can reduce performance.
- **Max Active Survivors** normally caps how many production survivors may be physically materialized at once. The balanced default is 16 and the supported range is 1–48. Disabling caps ignores this setting; the scheduler still builds at most two new bodies per population update instead of loading a whole settlement in one burst. This rate limit does not impose a total-body cap.
- **Population Refill Days** defaults to five days. Set it to **0** for a finite starting population with no routine replacements or uncapped arrivals. Existing people remain, and separate Knox Events have their own controls. Re-enabling refill starts a full interval; missed arrivals never accumulate.
- **Minimum Spawn Distance** defaults to 40 tiles and keeps first materialization away from local players and out of view. Saved survivors always restore at their exact recorded square once it is loaded.
- **Companion Limit** controls how many active companions each local player may recruit.
- **Follower Formation** selects **Paired** (default) or **Single File** behind the leader for companions and travelling groups. Single File is narrower and longer. These are preferred positions; native paths and blocked-tile recovery may break the formation.
- **Follower Spacing** controls grid separation from 1–3 tiles per axis, default 1. Larger spacing places rear members farther behind. Neither setting controls combat positioning or vehicles.
- **Survivor Encounter Distance** is effectively at least ten tiles beyond Minimum Spawn Distance, preserving a usable first-appearance band even when configured values overlap. Hidden, loaded, safe-square requirements still apply.
- **Allow NPC Factions (Work in Progress)** controls new faction formation and base scouting. It remains enabled for the intended living-world test loop. Existing factions remain intact when disabled.
- **Enable Knox Events (Experimental)** is off by default. It controls dispatch and processing of scripted faction/named-world events; event records are preserved, and the setting can be enabled later for focused testing.
- **Survivors Needed to Form a Faction** defaults to four (range 3-8). Smaller travelling groups remain informal, and reaching the number still does not bypass the existing shared-survival relationship requirement.
- **Maximum NPC Faction Members** defaults to eight (range 3-24), with an effective minimum equal to Survivors Needed to Form a Faction. It limits future recruitment; lowering it never removes existing members or affects player-owned groups.
- **Allow Hostile Survivor Encounters (Experimental)** controls threats and robberies between independent survivors. It remains enabled, but human encounter/combat behavior is still being polished.
- **Allow Survivor Fleeing (Experimental)** defaults off. Enabling it restores combat-risk retreat behavior. Survivors still perceive, fight and defend themselves while it is disabled; only autonomous retreat ownership is suppressed while escape routing receives more live testing.
- **Allow Experimental NPC Driving** defaults off. When enabled, a companion can use **Drive Ahead** from their Orders while the player is a passenger in an already-running driveable vehicle. The driver seat must be free; the order uses a short loaded lane and releases controls at its target or if the lane becomes invalid. Longer destinations and convoys remain future live gates.
- **Allow Faction Raids (Experimental)** defaults off. Players may opt into the real-member raid system; the first possible raid defaults to day 14.
- **Allow Survivor and Player Combat (Experimental)** remains enabled so hostile relationships can resolve naturally, but human combat is still being polished.
- **Automatic NPC Base Work Areas** defaults on. Autonomous NPC factions receive practical guard, patrol, farming, wood, corpse, and storage defaults. Player bases remain manually configured through the Notebook.
- **Show Companion HUD** controls the right-side companion panel.
- **Show Survivor Activity Feed** controls the Knox message window. Speech bubbles still work.

Production population uses real Build 42 player starts and supplemental ground-floor building locations. Distant survivors retain virtual locations and nearby loaded survivors materialize only when safe. Dead origins remain reserved. Disabling caps never recycles dead identities or repeatedly spawns a batch after a long time skip. Re-enabling caps does not delete existing survivors or forcibly dismiss companions. With caps disabled, a starting population of zero can still receive later gradual arrivals.

The balanced defaults are intended to make a survivor encounter plausible during ordinary exploration without placing NPCs around every corner. Forty-eight is a whole-map population, not a local count. The 16-body active cap is only a performance ceiling; it does not force 16 survivors to stay near the player. The shorter hidden spawn buffer improves the chance of crossing paths while still preventing visible pop-in, while the slower refill preserves the value of each death.

Sandbox defaults are copied into a save when its sandbox rules are created. Existing saves may retain their old values and should be adjusted manually or replaced with a new playtest save when validating this balance.

## Developer tools

Developer tools are disabled by default. Enable **Knox Survivors - Developer Tools > Enable Developer Tools** before creating or loading the test save.

Detailed developer diagnostics also default off. Turn them on only for a focused test that needs periodic controller and render snapshots; ordinary error reporting remains available without the periodic status dump.

The automatic scenario can load one survivor, one companion, a two-person travel group, a three-person faction, or a faction that immediately starts using the normal base-scouting behavior. Leave it on **None** to spawn scenarios manually.

With developer tools enabled, right-click the world and open **Knox Survivors - Developer Tools**. The menu separates persistent survivor-population presets from one-click combat presets. Combat presets cover survivor, travel-group, faction, and stress-test fights; they report results automatically and can write a detailed combat snapshot to `console.txt`. Cleanup removes only zombies created by the active combat preset.

Every test survivor receives an isolated, save-persistent `ks-dev-*` identity. Each automatic scenario keeps its own identities, so changing scenarios cannot accidentally recruit or regroup somebody left over from a different test. Spawning a scenario is therefore a real persistence test, not a disposable visual prop. Destructive tests remain behind their own off-by-default option.
