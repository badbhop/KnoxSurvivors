<!-- modforge-doc
authority: reference
load: on-demand
purpose: retirement notice for the deprecated Knox Survivors Launcher
-->

# Knox Survivors Launcher — retired

The separate Knox Survivors Launcher is deprecated, unsupported, and not part
of current Knox Survivors releases. Do not download, distribute, or use old
launcher archives. The owner has requested that its source repository become
private; until that setting is confirmed, do not treat its public page or old
releases as supported downloads.

## Current player setup

Use KnoxBridge Runtime as the only supported Knox Java startup path:

1. Subscribe to Knox Survivors and its required KnoxBridge Runtime Workshop
   item, and let Steam finish downloading both.
2. Download the official player setup package from
   [KnoxBridge GitHub Releases](https://github.com/exe-create/KnoxBridge/releases/latest).
3. Follow the current [KnoxBridge installation guide](https://github.com/exe-create/KnoxBridge/blob/main/docs/INSTALLATION.md).
4. Enable Knox Survivors in the Project Zomboid Mods menu and launch normally
   through Steam.

KnoxBridge and ZombieBuddy are separate alternatives. Never configure or run
both instrumentation runtimes in one Project Zomboid process. The old direct
Knox agent path is not a user setup option.

## Existing installs

This retirement changes the supported setup instructions; it does not delete
Project Zomboid saves or automatically alter player saves. Stop launching via
the old app. If KnoxBridge reports a competing runtime, close the game and
remove the old Knox launch configuration using the tool that created it, then
install KnoxBridge according to its current guide. Back up the game configuration
before changing it. Do not stack the old agent with KnoxBridge.

Historical launcher implementation and release notes are retained for
reference only. They do not override current KnoxBridge instructions or
establish current Build 42 compatibility.
