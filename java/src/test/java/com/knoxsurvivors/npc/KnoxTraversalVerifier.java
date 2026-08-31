package com.knoxsurvivors.npc;

import java.util.List;

/** Focused traversal-policy and route-continuation checks without a running game. */
public final class KnoxTraversalVerifier {
    private KnoxTraversalVerifier() {
    }

    public static void main(String[] args) {
        verifyNonDestructivePolicy();
        verifyExactEdgeSuppression();
        verifyInteractionOwnershipAndRouteContinuation();
        System.out.println(
            "KnoxTraversalVerifier PASS native=true nondestructive=true"
                + " exactEdge=true continuation=true interruption=true"
        );
    }

    private static void verifyNonDestructivePolicy() {
        require(KnoxTraversalPolicy.doorAction(true, false)
            == KnoxTraversalPolicy.DoorAction.PASS, "open door passes");
        require(KnoxTraversalPolicy.doorAction(false, false)
            == KnoxTraversalPolicy.DoorAction.TRY_NATIVE_OPEN,
            "closed door delegates one open attempt to native logic");
        require(KnoxTraversalPolicy.doorAction(false, true)
            == KnoxTraversalPolicy.DoorAction.FAIL_BARRICADED,
            "barricaded door fails without damage");

        require(KnoxTraversalPolicy.windowAction(false, false, false, false, "NONE")
            == KnoxTraversalPolicy.WindowAction.TRY_NATIVE_OPEN,
            "closed window delegates one open attempt to native logic");
        require(KnoxTraversalPolicy.windowAction(
            false, false, false, false, "OPEN_ATTEMPTED"
        ) == KnoxTraversalPolicy.WindowAction.FAIL_UNUSABLE,
            "failed window open does not authorize smashing");
        require(KnoxTraversalPolicy.windowAction(true, false, false, true, "OPEN_COMPLETED")
            == KnoxTraversalPolicy.WindowAction.CLIMB, "open climbable window climbs");
        require(KnoxTraversalPolicy.windowAction(false, true, false, true, "NONE")
            == KnoxTraversalPolicy.WindowAction.CLIMB, "broken climbable window climbs");
        require(KnoxTraversalPolicy.windowAction(false, false, true, false, "NONE")
            == KnoxTraversalPolicy.WindowAction.FAIL_BARRICADED,
            "barricaded window fails without damage");
    }

    private static void verifyExactEdgeSuppression() {
        KnoxNpc npc = new KnoxNpc("edge-test", new Object(), 0, 0, 0);
        npc.rememberTraversalFailure(1, 1, 0, 2, 1, 0, "FAILED_LOCKED_DOOR");
        require(npc.isTraversalCoolingDown(1, 1, 0, 2, 1, 0),
            "failed edge enters cooldown");
        require(!npc.isTraversalCoolingDown(1, 1, 0, 1, 2, 0),
            "different edge remains available for alternate route");
    }

    private static void verifyInteractionOwnershipAndRouteContinuation() {
        KnoxNpc npc = new KnoxNpc("route-test", new Object(), 0, 0, 0);
        Object firstEdge = new Object();
        Object replacementEdge = new Object();
        npc.setMovementRoute(List.of(
            new float[] { 1.5f, 0.5f, 0.0f },
            new float[] { 2.5f, 0.5f, 0.0f }
        ));
        npc.useTraversalInteractionTarget(firstEdge);
        npc.setTraversalInteractionStage("OPEN_ATTEMPTED");
        npc.useTraversalInteractionTarget(firstEdge);
        require("OPEN_ATTEMPTED".equals(npc.getTraversalInteractionStage()),
            "same edge retains its native interaction stage");
        npc.useTraversalInteractionTarget(replacementEdge);
        require("NONE".equals(npc.getTraversalInteractionStage()),
            "changed world edge invalidates stale interaction intent");

        npc.advanceMovementRoute();
        require(npc.hasMovementRoute(),
            "crossing one obstacle node preserves the final route destination");
        require(npc.getTraversalInteractionTarget() == null,
            "crossed edge releases temporary traversal ownership");

        npc.useTraversalInteractionTarget(firstEdge);
        npc.setTraversalInteractionStage("OPEN_ATTEMPTED");
        npc.clearMovementRoute();
        require(!npc.hasMovementRoute() && npc.getTraversalInteractionTarget() == null
            && "NONE".equals(npc.getTraversalInteractionStage()),
            "interruption releases route and traversal sub-action together");
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new IllegalStateException(message);
        }
    }
}
