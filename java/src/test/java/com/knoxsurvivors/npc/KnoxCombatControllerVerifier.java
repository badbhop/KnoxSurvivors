package com.knoxsurvivors.npc;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.List;
import java.util.Map;
import zombie.iso.IsoGridSquare;

/** Focused terminal combat cleanup checks that do not require a running game. */
public final class KnoxCombatControllerVerifier {
    private KnoxCombatControllerVerifier() {
    }

    public static void main(String[] arguments) throws Exception {
        require(KnoxCombatController.recoveryTicks(false) == 30
            && KnoxCombatController.recoveryTicks(true) == 24,
            "small melee recovery increase must not slow firearms");
        require(KnoxCombatController.clampAimSettleTicks(0) == 8
            && KnoxCombatController.clampAimSettleTicks(18) == 18
            && KnoxCombatController.clampAimSettleTicks(99) == 30,
            "aim settle input remains bounded for native combat");
        FakeBody body = new FakeBody();
        KnoxNpc npc = new KnoxNpc("combat-verifier", body, 10, 20, 0);
        npc.setMovementRoute(List.of(new float[] {11.5f, 20.5f, 0.0f}));

        KnoxCombatController controller = new KnoxCombatController();
        Field npcField = KnoxCombatController.class.getDeclaredField("npc");
        npcField.setAccessible(true);
        npcField.set(controller, npc);
        Field combatWeaponField = KnoxCombatController.class.getDeclaredField("combatWeapon");
        combatWeaponField.setAccessible(true);
        combatWeaponField.set(controller, new Object());
        npc.setCombatActive(true);
        controller.reset();

        require(!body.isAiming, "terminal cleanup clears aiming");
        require(!body.authorizeMelee, "terminal cleanup clears melee authorization");
        require(!body.authorizeShoveStomp, "terminal cleanup clears shove/stomp authorization");
        require(!body.initiateAttack, "terminal cleanup clears attack initiation");
        require(!body.attackStarted, "terminal cleanup clears attack-started flag");
        require(!body.aimAtFloor, "terminal cleanup clears floor aim");
        require(!body.isCharging && body.useChargeDelta == 0.0f,
            "terminal cleanup clears charge input");
        require(body.attackType.isEmpty(), "terminal cleanup clears AttackType");
        require(body.attackTargetSquare == null, "terminal cleanup clears attack target square");
        require(!body.controlVars.aiming && !body.controlVars.initiateAttack,
            "terminal cleanup clears AI attack input");
        require(!body.controlVars.melee && !body.controlVars.bannedAttacking,
            "terminal cleanup clears stale AI melee gates");
        require(body.pathfinder.cancelled, "terminal cleanup cancels combat pathfinder");
        require(!npc.hasMovementRoute(), "terminal cleanup releases combat route");
        require(combatWeaponField.get(controller) == null,
            "terminal cleanup releases ranged weapon ownership");
        require(!npc.isCombatActive(),
            "terminal cleanup releases combat locomotion ownership");
        require(KnoxCombatController.unavailable(true, false),
            "dead combatant is immediately invalid");
        require(KnoxCombatController.unavailable(false, true),
            "detached combatant is immediately invalid");
        require(!KnoxCombatController.unavailable(false, false),
            "live loaded combatant remains valid");
        float meleeRange = KnoxCombatController.desiredRange(false, 1.25f, 0.0f);
        float attackEntry = KnoxCombatController.attackEntryThreshold(meleeRange);
        float reapproach = KnoxCombatController.reapproachThreshold(meleeRange);
        require(Math.abs(meleeRange - 0.85f) < 0.0001f,
            "melee policy keeps a safe margin inside native adjusted reach");
        require(attackEntry < reapproach,
            "attack entry is closer than reapproach hysteresis");
        require(attackEntry < 1.25f,
            "attack entry remains inside native melee reach");
        npc.setMovementRoute(List.of(new float[] {meleeRange, 0, 0}));
        npc.setCombatActive(true);
        require(meleeRange + npc.movementNodeTolerance() < attackEntry,
            "final combat waypoint cannot finish outside attack-entry tolerance");
        npc.setCombatActive(false);
        require(npc.movementNodeTolerance() == 0.35f,
            "ordinary route arrival tolerance is unchanged");
        require(KnoxCombatController.shouldRefreshApproach("Succeeded", false, 30),
            "completed stale approach is reconsidered instead of waiting forever");
        require(KnoxCombatController.shouldRefreshApproach("ManualRoute", true, 30),
            "moving zombie refreshes a live route at bounded cadence");
        require(!KnoxCombatController.shouldRefreshApproach("ManualRoute", true, 29),
            "moving target cannot refresh every frame");
        require(!KnoxCombatController.shouldRefreshApproach("Transition:CLIMBING", true, 90),
            "target movement does not cancel an active traversal");
        require(!KnoxCombatController.targetMovedSinceApproach(0.5f, 0, 0, 0),
            "small target drift does not cause route churn");
        require(KnoxCombatController.targetMovedSinceApproach(0.8f, 0, 0, 0),
            "meaningful target movement causes bounded re-engagement");
        float desiredRange = KnoxCombatController.desiredRange(true, 15.0f, 0.0f);
        float minimumRange = KnoxCombatController.minimumRangedDistance(desiredRange);
        require(desiredRange > minimumRange && desiredRange <= 15.0f,
            "firearm policy chooses a useful bounded firing range");
        require(KnoxCombatController.shouldRepositionRanged(
            true, minimumRange - 0.1f, minimumRange, 61, 0, false
        ), "close ready firearm requests bounded reposition");
        require(!KnoxCombatController.shouldRepositionRanged(
            true, minimumRange - 0.1f, minimumRange, 30, 0, false
        ), "firearm reposition cooldown prevents request churn");
        require(!KnoxCombatController.shouldRepositionRanged(
            true, minimumRange - 0.1f, minimumRange, 61, 0, true
        ), "active firearm attack is not interrupted by reposition");
        require(!KnoxCombatController.shouldRepositionRanged(
            false, 0.5f, minimumRange, 61, 0, false
        ), "melee positioning is not changed by firearm policy");
        Method requestAttack = KnoxCombatController.class.getDeclaredMethod(
            "requestAttack", Object.class, boolean.class, boolean.class
        );
        requestAttack.setAccessible(true);
        Field unarmedField = KnoxCombatController.class.getDeclaredField("unarmedCombat");
        unarmedField.setAccessible(true);
        unarmedField.setBoolean(controller, false);
        requestAttack.invoke(controller, body, false, true);
        require(body.authorizeMelee,
            "Build 42 general attack authorization remains enabled for firearms");
        require(!body.authorizeShoveStomp,
            "firearm request does not authorize shove/stomp");
        require(!body.doShove,
            "firearm request clears stale shove mode before native attackHook");
        require(body.pressedAttackCount == 0,
            "Java firearm request yields to native Lua attack hook");
        unarmedField.setBoolean(controller, true);
        requestAttack.invoke(controller, body, false, false);
        require(body.authorizeShoveStomp,
            "unarmed standing request authorizes native shove/stomp");
        require(body.doShove,
            "unarmed request explicitly selects the native shove path");
        require(body.pressedAttackCount == 1,
            "unarmed request enters the native hand-to-hand attack path");
        Method clearAttack = KnoxCombatController.class.getDeclaredMethod("clearAttackIntent");
        clearAttack.setAccessible(true);
        npcField.set(controller, npc);
        clearAttack.invoke(controller);
        require(!body.isAiming && !body.controlVars.aiming
                && !body.controlVars.initiateAttack && !body.initiateAttack,
            "ranged reposition can clear every native attack input before movement");
        require(!KnoxCombatController.allowsDirectSwipeFallback(true),
            "ranged attack cannot fall through to the melee SwipeState fallback");
        require(KnoxCombatController.allowsDirectSwipeFallback(false),
            "existing melee fallback remains available");
        require(KnoxCombatController.liveTargetMode(false),
            "live combat mode permits an engine human target");
        require(!KnoxCombatController.liveTargetMode(true),
            "controlled zombie gate remains zombie-only");

        Method ready = KnoxCombatController.class.getDeclaredMethod("applyReadyPosture", Object.class);
        ready.setAccessible(true);
        ready.invoke(null, body);
        require(body.isAiming && body.controlVars.aiming, "recovery retains native aiming posture");
        require(!body.controlVars.initiateAttack && !body.initiateAttack && !body.attackStarted
            && body.attackType.isEmpty(), "ready posture cannot rearm the completed attack or block bite gate");
        System.out.println(
            "KnoxCombatControllerVerifier PASS attackFlags=true route=true ownership=true ranged=true stealth=true"
        );
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new AssertionError(message);
        }
    }

    public static final class FakeBody {
        public boolean isCharging = true;
        public float useChargeDelta = 36.0f;
        boolean isAiming = true;
        boolean authorizeMelee = true;
        boolean authorizeShoveStomp = true;
        boolean initiateAttack = true;
        boolean attackStarted = true;
        boolean aimAtFloor = true;
        boolean doShove = true;
        boolean zombiesDontAttack = true;
        boolean bannedAttacking;
        int pressedAttackCount;
        String attackType = "swing";
        IsoGridSquare attackTargetSquare;
        final FakePathfinder pathfinder = new FakePathfinder();
        final FakeControlVars controlVars = new FakeControlVars();
        final FakeAiComponent aiComponent = new FakeAiComponent(controlVars);

        public void setIsAiming(boolean value) { isAiming = value; }
        public void setAuthorizeMeleeAction(boolean value) { authorizeMelee = value; }
        public void setAuthorizeShoveStomp(boolean value) { authorizeShoveStomp = value; }
        public void setInitiateAttack(boolean value) { initiateAttack = value; }
        public void setAttackStarted(boolean value) { attackStarted = value; }
        public void setAimAtFloor(boolean value) { aimAtFloor = value; }
        public void setDoShove(boolean value) { doShove = value; }
        public void setZombiesDontAttack(boolean value) { zombiesDontAttack = value; }
        public void setBannedAttacking(boolean value) { bannedAttacking = value; }
        public void pressedAttack() { pressedAttackCount++; }
        public void clearHandToHandAttack() { }
        public void clearVariable(String name) {
            if ("AttackType".equals(name)) {
                attackType = "";
            }
        }
        public void setAttackTargetSquare(IsoGridSquare square) { attackTargetSquare = square; }
        public Object getECSComponentMap() throws ClassNotFoundException {
            return Map.of(
                Class.forName("zombie.characters.component.AIComponent"),
                aiComponent
            );
        }
        public FakePathfinder getPathFindBehavior2() { return pathfinder; }
    }

    public static final class FakePathfinder {
        boolean cancelled;
        public void cancel() { cancelled = true; }
    }

    public static final class FakeAiComponent {
        private final FakeControlVars controlVars;
        FakeAiComponent(FakeControlVars controlVars) { this.controlVars = controlVars; }
        public FakeControlVars getHumanControlVars() { return controlVars; }
    }

    public static final class FakeControlVars {
        public boolean aiming = true;
        public boolean melee = true;
        public boolean bannedAttacking = true;
        public boolean initiateAttack = true;
    }
}
