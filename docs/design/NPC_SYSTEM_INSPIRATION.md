<!-- modforge-doc
authority: canonical
load: on-demand
purpose: NPC-system design direction derived from owner research and current Knox implementation
-->

# Knox Survivors — NPC system design direction

Updated: 2026-09-26

## Core rule

> **A Knox survivor is another Project Zomboid survivor controlled by AI, not a colony-game pawn.**

Project Zomboid remains the foundation. Other games are references for solving specific AI/design problems, not templates to copy wholesale.

The desired result is a living human population whose survivors:

- have persistent identity, history, relationships, possessions, health, skills and responsibilities;
- physically use Project Zomboid's real world, items, containers, actions and combat while loaded;
- continue the same goals in a cheaper abstract form while unloaded;
- make choices without requiring constant player micromanagement;
- remain rare enough that individuals, deaths, specialists and factions matter.

## Research provenance

This direction was promoted from the owner's 2026-09-26 research notes covering:

- Project Zomboid's published NPC/metaverse concepts;
- RimWorld;
- Survivalist: Invisible Strain;
- State of Decay 2;
- Rebuild 3;
- Dead State.

The research is inspiration only. No proprietary code, assets, text, data, or exact implementations from those games are to be copied.

## What each reference contributes

| Reference | Useful lesson for Knox | What Knox should avoid |
|---|---|---|
| Project Zomboid NPC plans | Loaded ↔ off-screen continuity, persistent people, groups, goals, world events and simplified distant simulation | Simulating full physical AI across the whole map |
| RimWorld | One concrete job at a time, work priorities, job claims/reservations, storage priority | Turning humans into programmable colony pawns |
| Survivalist: Invisible Strain | Prioritized roles, autonomous communities, social memories, relationships, organized storage | Requiring the player to micromanage every survivor |
| State of Decay 2 | Individual usefulness, specialists, community pressure and consequences when a useful survivor is lost | Converting Project Zomboid's real items into generic resource counters |
| Rebuild 3 | Group-level goals, missions, faction decisions, survivor specialties and generated events | Turning Knox into a strategy-map game |
| Dead State | Base responsibilities driven by actual shortages/problems, specialists and useful facilities | Depending on scripted crisis events for normal life |

### Primary research links

- Project Zomboid, current planned-features page (still lists NPC survivors driven by off-screen survival): https://projectzomboid.com/blog/the-game/
- Project Zomboid, *The Zuckerverse* (off-screen storylets and explicit Crusader Kings inspiration): https://projectzomboid.com/blog/news/2022/03/the-zuckerverse/
- Project Zomboid, *The Coding of the Living Dead*: https://projectzomboid.com/blog/news/2012/10/the-coding-of-the-living-dead/
- Project Zomboid, NPC/metagame discussion: https://projectzomboid.com/blog/news/2014/07/its-an-npc-related-mondoid1-no-hype-pls/
- Project Zomboid, *Lone Survivor*: https://projectzomboid.com/blog/news/2022/04/lone-survivor/
- Project Zomboid, *On the Verge*: https://projectzomboid.com/blog/news/2013/07/on-the-verge/
- RimWorld hauling/work reference: https://rimworldwiki.com/wiki/Hauling and https://rimworldwiki.com/index.php?title=Work
- Survivalist: Invisible Strain: https://store.steampowered.com/app/1054510/
- Survivalist multiple roles / storage policy / Organizer patch: https://steamdb.info/patchnotes/9371355/
- Survivalist organizer-role conflict + gossip/memory decay patch: https://steamdb.info/patchnotes/13486262/
- State of Decay 2 official player guide: https://www.stateofdecay.com/wp-content/uploads/2022/07/PlayerGuide.pdf
- Rebuild 3: https://www.rebuildgame.com/about.php and https://store.steampowered.com/app/257170/
- Dead State jobs/allies references: https://deadstate.fandom.com/wiki/Jobs and https://deadstate.fandom.com/wiki/Allies

## 2026 research verification and one useful addition

The research direction still matches Project Zomboid's current public plan: its official game page continues to describe planned NPC survivors as using a system that tracks off-screen survival. The 2022 NPC framework article describes the unloaded world as a simplified, event-driven **storylet** simulation rather than full physical pathfinding everywhere.

That article also explicitly names **Crusader Kings** as an inspiration for dynamic NPC stories. For Knox, the useful lesson is narrow:

- create reusable event/storylet templates with clear conditions;
- feed them real survivor traits, relationships, group state, location and shortages;
- let outcomes update persistent state and memories;
- materialize only the physical consequences that matter when the survivor returns to the loaded world.

Do **not** turn Knox into a grand-strategy character simulator. Crusader Kings belongs in the research set specifically for procedural story/event structure, while Project Zomboid remains the simulation and gameplay foundation.

## Operating model

Every survivor should converge on this loop:

`persistent survivor state`
→ `decision / priority arbitration`
→ `one primary job`
→ `physical or abstract execution`
→ `result / world consequences`
→ `state, relationship and history updates`
→ `choose again`

### The key ownership rule

A survivor normally has:

**one primary intention + one active job + emergency reactions**

Emergency survival/combat can interrupt a job. It should not create multiple permanent systems fighting for movement/action ownership.

This is an architectural direction, not a request to rewrite every existing Knox controller at once.

## Priority hierarchy

The exact numeric weights may remain internal, but the conceptual ordering should be approximately:

1. immediate survival;
2. life-saving emergency;
3. critical physical need;
4. active combat/threat response;
5. direct player commitment/order;
6. group/base responsibility;
7. assigned role/preference;
8. ordinary autonomous work;
9. social/personal/free activity.

A lower layer should not continuously steal ownership from a valid higher layer.

## Universal job lifecycle target

Existing Knox systems should gradually expose the same lifecycle questions:

- Can this job start?
- Why should it start now?
- What survivor owns it?
- What items, destination, container, bed, corpse, vehicle, target or worksite does it reserve?
- What can interrupt it?
- Can it resume?
- What invalidates it?
- What happens on failure?
- What happens on completion?
- Is there a safe off-screen equivalent?
- What state must be reconciled when the survivor materializes again?

Barricading remains barricading. Corpse hauling remains corpse hauling. Firearms remain firearms. Scavenging remains scavenging. The goal is shared operating rules around those systems, not replacement for replacement's sake.

## Current repository mapping

The current Knox worktree already contains much of the foundation. The table below distinguishes **existing implementation** from the broader design target.

| Design concept | Current Knox foundation | Current status / gap |
|---|---|---|
| Decision owner | `KS_SurvivorAutonomyController.lua` and `KS_SurvivorAutonomy.lua` | **Partial.** There is a central autonomy/controller path, but not every behavior is expressed through one universal job contract yet. |
| Reservations / claims | autonomy reservation tables, `KS_BaseTaskBoard.lua`, base-task claims, group/support leases | **Partial.** Strong subsystem claims exist; a single shared reservation API across every job type does not yet exist. |
| Base needs | `KS_BaseNeeds.lua`, `KS_BaseJobs.lua`, `KS_BaseSupplyPlanner.lua` | **Implemented foundation.** Needs can influence base work and supplies; this can grow into broader mission generation. |
| Work priority / roles | `KS_BaseJobs.lua`, survivor origin/job preferences, duty scheduling | **Implemented foundation.** Preferences and task eligibility exist; richer prioritized multi-role profiles remain a design direction. |
| Organized storage | `KS_BaseStorage.lua`, `KS_BaseOrganize.lua`, supply planner | **Implemented/active work.** Current organizer code already avoids reserved items and re-resolves destinations. |
| Group planning | `KS_GroupScavenge.lua`, travel groups, away-team/event systems | **Partial.** Specific coordinated group behaviors exist; there is not yet one generic planner converting any group need into a mission. |
| Persistent relationships | `KS_Persistence.lua`, `KS_SurvivorRelationships.lua` | **Implemented foundation.** Meetings, shared activity, trust/disposition and faction relationships are persisted. |
| Event → memory → relationship | relationship encounter history, off-screen stories/events | **Partial.** Gameplay history exists, but a general-purpose named memory ledger with decay/gossip/consequences is not yet a universal system. |
| Loaded ↔ unloaded continuity | `KS_UnloadedSurvival.lua`, persistence, lifecycle policy, off-screen stories | **Implemented foundation.** Same survivor persists through loaded/hibernated states; additional job equivalence and reconciliation can be generalized. |
| World evidence after off-screen events | `KS_WorldTraces.lua`, event runtime | **Implemented/active work.** Abstract events can leave materialized traces rather than disappearing as pure text. |
| Materialization / reconciliation | persistence capture/restore, lifecycle and population systems | **Implemented foundation.** This remains one of the highest-risk areas and must stay identity-safe. |
| Rare meaningful population | world population, groups/factions/camps | **Existing policy direction.** Balance values remain tunable; design should continue favoring significance over endless replacement. |

## Role design: preference, not a permanent caste

Avoid:

`Bob = Farmer forever`

Prefer a ranked capability/preference profile:

1. farming;
2. hauling;
3. repair;
4. guarding.

The survivor chooses the highest-priority valid work that the current group/base actually needs and that the survivor can perform.

Skills, traits, profession, equipment, health, relationships, current order and urgency may all affect suitability without making the survivor a colony pawn.

## Shared reservation direction

The research highlights a recurring failure mode: an organizer or generic worker can take an item another job requires.

Knox should continue moving toward a shared rule:

> Before taking or moving a resource, check whether an active job, loadout, survivor need or other reservation owns it.

Likely reservation categories include:

- item / stack;
- container or storage slot;
- work target;
- destination square;
- bed/rest point;
- corpse;
- barricade/window/door;
- vehicle/seat;
- combat target where exclusivity matters;
- support recipient;
- mission slot.

Reservations must expire or be released on completion, failure, interruption, hibernation and owner loss.

## Group needs should create missions

The individual survivor loop should not be the only planner.

Example:

`base food is low`
→ base need is raised
→ group planner decides a scavenging mission is justified
→ suitable members are selected
→ equipment/supplies are checked and reserved
→ the group travels
→ the mission continues abstractly if unloaded
→ real food is acquired or the mission fails
→ survivors return
→ storage/organizer places the supplies
→ shortage clears
→ participants gain history/memories
→ other groups may remember an encounter.

That is one story produced by existing systems feeding each other.

## Social memory direction

Relationships should primarily come from events that actually happened.

Prefer:

- Sarah abandoned Bob during a dangerous fight.
- Bob remembers the abandonment.
- Later Sarah rescues Bob while injured.
- The new event changes Bob's trust/disposition.

Avoid a disconnected Sims-style relationship minigame that invents arbitrary numbers without world history.

A future generalized memory record could contain:

- event type;
- participants;
- place/time;
- severity;
- witnessed/direct/heard-about source;
- relationship effects;
- decay policy;
- whether the event can be gossiped about;
- links to faction reputation or future decisions.

The current relationship and off-screen story systems are the starting point; this should not become a second competing relationship model.

## Specialists should matter because the world uses real systems

Keep real Project Zomboid food, medicine, ammo, fuel, tools, weapons and containers.

The lesson from State of Decay is not the abstract resource counter; it is that losing one capable person changes what a community can do.

Examples:

- losing the best mechanic makes vehicle maintenance harder;
- losing an experienced medical survivor makes serious injuries riskier;
- losing a strong shooter changes group combat capability;
- losing the primary farmer may force more scavenging.

These consequences should emerge from skills/capabilities and real work requirements rather than scripted punishment.

## Loaded and unloaded must be the same story

### Loaded

Use actual Project Zomboid state:

- body;
- inventory/equipment;
- needs/health;
- movement/pathing;
- combat;
- buildings/containers;
- timed/native actions.

### Unloaded

Keep the same:

- survivor ID;
- destination;
- mission;
- group;
- possessions/supplies;
- relationships;
- injuries/needs;
- important job/intent.

Use cheaper event/simulation logic instead of pretending the entire map is physically loaded.

On return, **materialize and reconcile the result**, never create a second contradictory version of the survivor.

## Recommended architectural growth path

These are design targets, not automatically approved implementation tasks.

### A. Formalize decision arbitration

Document one common intent/job ownership contract around the existing autonomy controller. First use it to describe current behavior; migrate systems only when doing so fixes a concrete ownership problem or enables an approved feature.

### B. Generalize reservations

Unify compatible existing claim/lease concepts behind shared ownership/release semantics without breaking specialized systems that already work.

### C. Generalize base/group need planning

Let shortage/problem detectors create needs. Let planners turn needs into missions/jobs. Do not let every survivor independently solve the same shortage.

### D. Expand role preferences and capability selection

Use skills, profession, traits, equipment and experience to decide who is suitable. Preserve flexible fallback work.

### E. Add an event/memory ledger

Build on current relationship history/off-screen stories. Record meaningful events once and let relationships, reputation, dialogue and future decisions consume that history.

### F. Expand off-screen job equivalents

Only abstract jobs whose effects can be represented safely. Physical world-changing work that cannot be reconciled safely should pause until loaded.

### G. Strengthen materialization reconciliation

Every abstract outcome must have an explicit, idempotent path back to real Project Zomboid state.

## Design guardrails

- Do not add twenty isolated systems when existing systems can be connected.
- Do not create a second persistence/relationship/base-work owner.
- Do not fabricate resources to make AI appear competent.
- Do not simulate world-changing work off-screen unless it can reconcile safely.
- Do not make direct player orders meaningless; emergency survival can interrupt, but normal autonomy should not constantly overwrite player commitments.
- Do not let every NPC independently react to a group-level shortage.
- Do not make humans so common that deaths and specialists stop mattering.
- Do not turn Knox into RimWorld, Rebuild, State of Decay, Dead State or Survivalist. Borrow the useful operating principle and translate it into Project Zomboid.

## Research still worth doing later

The current research is sufficient to guide the next architecture/design pass. Additional research is optional rather than blocking.

If deeper examples are useful later, the highest-value candidates are:

- **Crusader Kings** — deeper study of reusable story/event chains and character-context-driven outcomes; this is the most directly justified extra reference because Project Zomboid's own NPC article names it as an inspiration;
- **Kenshi** — persistent squads, jobs and autonomous settlement work;
- **Mount & Blade / Bannerlord** — parties, faction/world-level travel and conflict above individual agents;
- **Dwarf Fortress** — event-driven memories/relationships and needs, with careful filtering to avoid colony-game complexity.

Any new reference should be captured as a design/research item first and evaluated against the core Knox rule before becoming implementation work.
