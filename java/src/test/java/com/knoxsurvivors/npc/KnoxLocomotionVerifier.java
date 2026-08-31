package com.knoxsurvivors.npc;

/** Focused pace and physical-eligibility checks without a running game. */
public final class KnoxLocomotionVerifier {
    private KnoxLocomotionVerifier() {
    }

    public static void main(String[] args) {
        verifyPaceThresholds();
        verifyPhysicalEligibility();
        System.out.println(
            "KnoxLocomotionVerifier PASS walk=true run=true sprint=true"
                + " downgrade=true condition=true"
        );
    }

    private static void verifyPaceThresholds() {
        require(decide("normal", 20.0f).running() == false,
            "normal pace walks regardless of route length");
        KnoxLocomotionPolicy.Decision run = decide("run", 6.0f);
        require(run.running() && !run.sprinting(), "moderate catch-up runs");
        KnoxLocomotionPolicy.Decision sprint = decide("sprint", 15.0f);
        require(sprint.running() && sprint.sprinting(), "far eligible catch-up sprints");
        KnoxLocomotionPolicy.Decision closing = decide("sprint", 5.0f);
        require(closing.running() && !closing.sprinting(),
            "sprint request downgrades to run as the gap closes");
        require(!decide("sprint", 1.0f).running(),
            "catch-up drops to walking near the destination");
    }

    private static void verifyPhysicalEligibility() {
        KnoxLocomotionPolicy.Decision tired = KnoxLocomotionPolicy.decide(
            "sprint", 15.0f, 0.60f, 0.80f, 100.0f, true
        );
        require(tired.running() && !tired.sprinting(),
            "fatigue blocks sprint but still permits a run");
        KnoxLocomotionPolicy.Decision exhausted = KnoxLocomotionPolicy.decide(
            "sprint", 15.0f, 0.15f, 0.20f, 100.0f, true
        );
        require(!exhausted.running() && !exhausted.sprinting(),
            "low endurance forces walking");
        KnoxLocomotionPolicy.Decision injured = KnoxLocomotionPolicy.decide(
            "sprint", 15.0f, 0.80f, 0.20f, 20.0f, true
        );
        require(injured.running() && !injured.sprinting(),
            "low health blocks sprint");
        KnoxLocomotionPolicy.Decision engineDenied = KnoxLocomotionPolicy.decide(
            "sprint", 15.0f, 0.80f, 0.20f, 100.0f, false
        );
        require(engineDenied.running() && !engineDenied.sprinting(),
            "native canSprint remains authoritative");
    }

    private static KnoxLocomotionPolicy.Decision decide(String pace, float distance) {
        return KnoxLocomotionPolicy.decide(pace, distance, 0.80f, 0.20f, 100.0f, true);
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new IllegalStateException(message);
        }
    }
}
