package com.knoxsurvivors;

import com.knoxsurvivors.agent.KnoxAgent;
import com.knoxsurvivors.agent.KnoxCombatGate;
import com.knoxsurvivors.agent.KnoxHumanCombatGate;
import java.lang.StackWalker.StackFrame;
import java.util.Set;
import me.zed_0xff.zombie_buddy.Patch;

/**
 * ZombieBuddy 2.x compatibility hooks.
 *
 * <p>These use ZombieBuddy's supported Patch API instead of accessing its private
 * Instrumentation handle. The legacy Knox Launcher continues using Knox's original
 * ClassFileTransformers.</p>
 */
public final class KnoxZombieBuddyPatches {
    private static final Set<String> CALLBACK_METHODS = Set.of(
        "OnAnimEvent_AttackCollisionCheck",
        "OnAnimEvent_PlaySwingSound",
        "OnAnimEvent_PlaySwingSoundAlways"
    );

    private KnoxZombieBuddyPatches() { }

    /** Called from ZombieBuddy-inlined advice executing inside Project Zomboid classes. */
    public static boolean active() {
        return KnoxAgent.isZombieBuddyPatchRuntime() && !KnoxAgent.isLegacyRuntimeActive();
    }

    /** Called from ZombieBuddy-inlined advice executing inside Project Zomboid classes. */
    public static boolean localCombatCallsite() {
        return StackWalker.getInstance().walk(frames -> frames.limit(16).anyMatch(frame -> {
            String owner = frame.getClassName();
            String method = frame.getMethodName();
            return ("zombie.ai.states.SwipeStatePlayer".equals(owner)
                    && CALLBACK_METHODS.contains(method))
                || ("zombie.CombatManager".equals(owner)
                    && "attackCollisionCheck".equals(method));
        }));
    }

    /** Called from ZombieBuddy-inlined advice executing inside Project Zomboid classes. */
    public static boolean zombieVisibilityCallsite() {
        return StackWalker.getInstance().walk(frames -> frames.limit(16).anyMatch(
            KnoxZombieBuddyPatches::isZombieVisibilityFrame
        ));
    }

    private static boolean isZombieVisibilityFrame(StackFrame frame) {
        return "zombie.characters.IsoZombie".equals(frame.getClassName())
            && "isTargetVisible".equals(frame.getMethodName());
    }

    /** Static IsoPlayer.isLocalPlayer(IsoGameCharacter) used by the three melee callbacks. */
    @Patch(
        className = "zombie.characters.IsoPlayer",
        methodName = "isLocalPlayer",
        warmUp = true
    )
    public static class StaticLocalPlayerGate {
        @Patch.OnExit
        public static void exit(
            @Patch.Argument(0) Object character,
            @Patch.Return(readOnly = false) boolean result
        ) {
            if (!active() || result || !KnoxCombatGate.isKnoxShell(character)) return;
            if (localCombatCallsite()) result = true;
        }
    }

    /** Instance IsoPlayer.isLocalPlayer() used by CombatManager's impact-sound branch. */
    @Patch(
        className = "zombie.characters.IsoPlayer",
        methodName = "isLocalPlayer",
        warmUp = true,
        strictMatch = true
    )
    public static class InstanceLocalPlayerGate {
        @Patch.OnExit
        public static void exit(
            @Patch.This Object player,
            @Patch.Return(readOnly = false) boolean result
        ) {
            if (!active() || result || !KnoxCombatGate.isKnoxShell(player)) return;
            if (localCombatCallsite()) result = true;
        }
    }

    /** Preserve native checkPVP except for the same Knox single-player pairs already authorized. */
    @Patch(
        className = "zombie.CombatManager",
        methodName = "checkPVP",
        warmUp = true
    )
    public static class HumanPvpGate {
        @Patch.OnExit
        public static void exit(
            @Patch.Argument(0) Object attacker,
            @Patch.Argument(1) Object victim,
            @Patch.Return(readOnly = false) boolean result
        ) {
            if (!active()) return;
            Boolean override = KnoxHumanCombatGate.overridePVP(attacker, victim);
            if (override != null) result = override;
        }
    }

    /** Capture the Knox shell immediately inside IsoZombie.isTargetVisible(). */
    @Patch(
        className = "zombie.characters.IsoPlayer",
        methodName = "getIndex",
        warmUp = true,
        strictMatch = true
    )
    public static class VisibilityIndexCapture {
        @Patch.OnExit
        public static void exit(
            @Patch.This Object player,
            @Patch.Return int result
        ) {
            if (!active() || !KnoxCombatGate.isKnoxShell(player) || !zombieVisibilityCallsite()) return;
            KnoxCombatGate.captureTargetVisibilityIndexResult(player, result);
        }
    }

    /** Replace only the local-player lighting result for the pending Knox shell target. */
    @Patch(
        className = "zombie.iso.IsoGridSquare",
        methodName = "isCouldSee",
        warmUp = true
    )
    public static class VisibilitySquareGate {
        @Patch.OnExit
        public static void exit(
            @Patch.This Object square,
            @Patch.Argument(0) int playerIndex,
            @Patch.Return(readOnly = false) boolean result
        ) {
            if (!active() || !zombieVisibilityCallsite()) return;
            result = KnoxCombatGate.finishTargetVisibility(square, playerIndex, result);
        }
    }

    /** Never let a captured visibility target leak past the native visibility query. */
    @Patch(
        className = "zombie.characters.IsoZombie",
        methodName = "isTargetVisible",
        warmUp = true
    )
    public static class VisibilityCleanup {
        @Patch.OnExit(onThrowable = Throwable.class, suppress = Throwable.class)
        public static void exit() {
            if (active()) KnoxCombatGate.clearTargetVisibilityCandidate();
        }
    }

    /**
     * Runs after ZombieBuddy's patch pipeline is active and before gameplay begins.
     * Knox's existing fail-closed readiness gates remain in force until this executes.
     */
    @Patch(
        className = "zombie.gameStates.GameLoadingState",
        methodName = "exit",
        warmUp = true,
        strictMatch = true
    )
    public static class RuntimeReadyMarker {
        @Patch.OnExit
        public static void exit() {
            if (active()) KnoxCombatGate.markZombieBuddyPatchesReady();
        }
    }
}
