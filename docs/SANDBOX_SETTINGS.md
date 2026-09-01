# Sandbox settings

Knox Survivors adds two pages to Project Zomboid's sandbox options.

## Knox Survivors

- **Enable Knox Survivors** pauses the rebuild's gameplay entry points without deleting survivor save data.
- **World Population** sets the persistent starting population and, normally, the living-survivor target across the entire map. The balanced playtest default is 48 and the supported range is 0–256.
- **Disable Survivor Caps** is off by default. When enabled, the active-survivor and companion counts do not block activation or recruitment. World Population remains the starting count, but later arrivals may exceed it: at most one new identity per refill interval at an unused world location. Recruitment trust still applies when enabled; ownership, death, safe spawning and cooldown rules always apply. There is no separate numeric faction cap to bypass. Larger active populations can reduce performance.
- **Max Active Survivors** normally caps how many production survivors may be physically materialized at once. The balanced default is 16 and the supported range is 1–48. Disabling caps ignores this setting; the scheduler still builds at most two new bodies per population update instead of loading a whole settlement in one burst. This rate limit does not impose a total-body cap.
- **Population Refill Days** defaults to five days and controls how long a population deficit must persist before one replacement identity is allocated. Refill is gradual, one survivor per interval, never a catch-up burst.
- **Minimum Spawn Distance** defaults to 40 tiles and keeps first materialization away from local players and out of view. Saved survivors always restore at their exact recorded square once it is loaded.
- **Companion Limit** controls how many active companions each local player may recruit.
- **Require Trust to Recruit** is off by default, allowing an eligible independent survivor to be recruited immediately. Enable it to require 50 personal trust and use the existing refusal cooldown. It never permits recruiting hostile, dead, unavailable, grouped, or faction-owned survivors and does not bypass the companion limit.
- **Allow NPC Factions (Work in Progress)** controls new faction formation and base scouting. It remains enabled for the intended living-world test loop. Existing factions remain intact when disabled.
- **Allow Hostile Survivor Encounters (Experimental)** controls threats and robberies between independent survivors. It remains enabled, but human encounter/combat behavior is still being polished.
- **Allow Faction Raids (Experimental)** defaults off. Players may opt into the real-member raid system; the first possible raid defaults to day 14.
- **Allow Survivor and Player Combat (Experimental)** remains enabled so hostile relationships can resolve naturally, but human combat is still being polished.
- **Show Companion HUD** controls the right-side companion panel.
- **Show Survivor Activity Feed** controls the Knox message window. Speech bubbles still work.

Production population uses real Build 42 player starts and supplemental ground-floor building locations. Distant survivors retain virtual locations and nearby loaded survivors materialize only when safe. Dead origins remain reserved. Disabling caps never recycles dead identities or repeatedly spawns a batch after a long time skip. Re-enabling caps does not delete existing survivors or forcibly dismiss companions. With caps disabled, a starting population of zero can still receive later gradual arrivals.

The balanced defaults are intended to make a survivor encounter plausible during ordinary exploration without placing NPCs around every corner. Forty-eight is a whole-map population, not a local count. The 16-body active cap is only a performance ceiling; it does not force 16 survivors to stay near the player. The shorter hidden spawn buffer improves the chance of crossing paths while still preventing visible pop-in, while the slower refill preserves the value of each death.

Sandbox defaults are copied into a save when its sandbox rules are created. Existing saves may retain their old values and should be adjusted manually or replaced with a new playtest save when validating this balance.

## Developer tools

Developer tools are disabled by default. Enable **Knox Survivors - Developer Tools > Enable Developer Tools** before creating or loading the test save.

The automatic scenario can load one survivor, one companion, a two-person travel group, a three-person faction, or a faction that immediately starts using the normal base-scouting behavior. Leave it on **None** to spawn scenarios manually.

With developer tools enabled, right-click the world and open **Knox Survivors - Developer Tools**. The menu separates persistent survivor-population presets from one-click combat presets. Combat presets cover survivor, travel-group, faction, and stress-test fights; they report results automatically and can write a detailed combat snapshot to `console.txt`. Cleanup removes only zombies created by the active combat preset.

Every test survivor receives an isolated, save-persistent `ks-dev-*` identity. Each automatic scenario keeps its own identities, so changing scenarios cannot accidentally recruit or regroup somebody left over from a different test. Spawning a scenario is therefore a real persistence test, not a disposable visual prop. Destructive tests remain behind their own off-by-default option.
