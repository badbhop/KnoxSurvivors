package com.knoxsurvivors.npc;

/** Focused pace and physical-eligibility checks without a running game. */
public final class KnoxLocomotionVerifier {
    private KnoxLocomotionVerifier() {
    }

    public static void main(String[] args) {
        verifyPaceThresholds();
        verifyPhysicalEligibility();
        verifyNativeHealthScale();
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

    public static final class NativeHealth {
        public float getHealth() { return 1.0f; }
    }

    public static final class BodyHealth {
        private final float health;
        BodyHealth(float health) { this.health = health; }
        public float getOverallBodyHealth() { return health; }
    }

    public static final class InjuredHuman {
        public float getHealth() { return 1.0f; }
        public BodyHealth getBodyDamage() { return new BodyHealth(20.0f); }
    }

    private static void verifyNativeHealthScale() {
        float healthy = KnoxNpcFactory.locomotionHealth(new NativeHealth());
        require(healthy == 100.0f, "native health 1 means full health, not one percent");
        require(KnoxLocomotionPolicy.decide("sprint", 15, .8f, .2f, healthy, true).sprinting(),
            "healthy native character can actually sprint through the factory adapter");
        float injured = KnoxNpcFactory.locomotionHealth(new InjuredHuman());
        require(injured == 20.0f, "real BodyDamage overrides raw character health");
        require(!KnoxLocomotionPolicy.decide("sprint", 15, .8f, .2f, injured, true).sprinting(),
            "real injury still prevents sprinting");
        require(KnoxNpcFactory.locomotionHealth(new Object()) == 0.0f,
            "unreadable health fails conservatively");
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
