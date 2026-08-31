package com.knoxsurvivors.npc;

/** Focused ownership-state regression checks that do not require a running game. */
public final class KnoxMovementRequestVerifier {
    private KnoxMovementRequestVerifier() {
    }

    public static void main(String[] args) {
        verifyOwnershipMetadata();
        verifyZLevelGeometry();
        verifyRuntimeLifecycle();
        System.out.println(
            "KnoxMovementRequestVerifier PASS duplicate=true replacement=true cleanup=true"
                + " resume=true zLevel=true"
        );
    }

    private static void verifyZLevelGeometry() {
        require(KnoxMovementGeometry.arrived(10.5f, 20.5f, 1, 10.5f, 20.5f, 1, 0.65f),
            "same XYZ within tolerance arrives");
        require(!KnoxMovementGeometry.arrived(10.5f, 20.5f, 0, 10.5f, 20.5f, 1, 0.65f),
            "same XY on the wrong floor does not arrive");
        require(!KnoxMovementGeometry.nodeReached(
            10.5f, 20.5f, 0, 10.5f, 20.5f, 1, 0.35f
        ), "stair node is retained until its floor is reached");
        require(KnoxMovementGeometry.nodeReached(
            10.5f, 20.5f, 1, 10.5f, 20.5f, 1, 0.35f
        ), "floor transition releases the reached stair node");
    }

    private static void verifyOwnershipMetadata() {
        KnoxMovementRequest request = new KnoxMovementRequest();

        require(request.classify(10.5f, 20.5f, 0, false)
            == KnoxMovementRequest.Change.START, "inactive request starts");
        request.activate(10.5f, 20.5f, 0, false);
        require(request.isActive(), "request owns movement after activation");
        require(request.classify(10.5f, 20.5f, 0, false)
            == KnoxMovementRequest.Change.KEEP, "duplicate destination is suppressed");
        require(request.classify(11.5f, 20.5f, 0, false)
            == KnoxMovementRequest.Change.REPLACE, "changed destination replaces owner");
        require(request.classify(10.5f, 20.5f, 1, false)
            == KnoxMovementRequest.Change.REPLACE, "changed destination floor replaces owner");
        require(request.classify(10.5f, 20.5f, 0, true)
            == KnoxMovementRequest.Change.REPLACE, "crossing mode replaces normal movement");

        request.release();
        require(!request.isActive(), "completion or cancellation releases ownership");
        require(request.classify(11.5f, 20.5f, 0, false)
            == KnoxMovementRequest.Change.START, "released request can recover");

        request.activate(11.5f, 20.5f, 0, false);
        request.release();
        require(!request.isActive(), "failure cleanup releases ownership");
        request.activate(12.5f, 20.5f, 0, false);
        require(request.isActive(), "movement can resume after interruption");
    }

    private static void verifyRuntimeLifecycle() {
        FakeMovementEngine engine = new FakeMovementEngine();
        KnoxNpcRuntime runtime = new KnoxNpcRuntime(
            new KnoxNpc("movement-test", new Object(), 0, 0, 0),
            engine
        );
        Target first = new Target(10, 20, 0);
        Target replacement = new Target(10, 20, 1);

        require(runtime.beginMove(first, false).startsWith("MOVE_STARTED "),
            "first request starts");
        require(runtime.updateMovementPace("sprint")
            && "sprint".equals(runtime.npc().getMovementPace()),
            "active request accepts a pace-only update without replacement");
        require(runtime.beginMove(first, false).startsWith("MOVE_STARTED existing=true "),
            "duplicate request remains owned without restart");
        require(engine.starts == 1 && engine.cancels == 0,
            "duplicate request does not touch engine ownership");

        require(runtime.beginMove(replacement, false).startsWith("MOVE_STARTED replaced=true "),
            "replacement request starts after cancellation");
        require(engine.starts == 2 && engine.cancels == 1,
            "replacement cleans old engine request exactly once");
        require(engine.target.z == 1, "destination Z survives request construction");

        engine.tickResult = "Succeeded";
        engine.completeOnWrongFloor = true;
        require(runtime.tickMovement().startsWith("FailedWrongFloorOrPosition"),
            "engine XY completion on the wrong floor is rejected");
        require(engine.cancels == 2 && "IDLE".equals(runtime.tickMovement()),
            "wrong-floor completion releases ownership through normal failure cleanup");

        engine.completeOnWrongFloor = false;
        require(runtime.beginMove(replacement, false).startsWith("MOVE_STARTED "),
            "cross-floor request retries after bounded controller recovery");
        require("Succeeded".equals(runtime.tickMovement()), "correct-floor success is reported");
        require(engine.cancels == 3 && "IDLE".equals(runtime.tickMovement()),
            "success cleans engine state and releases ownership");

        require(runtime.beginMove(first, false).startsWith("MOVE_STARTED "),
            "new request starts after success");
        engine.failTick = true;
        require(runtime.tickMovement().startsWith("TICK_FAILED "),
            "tick exception is reported as failure");
        require(engine.cancels == 4 && "IDLE".equals(runtime.tickMovement()),
            "failure cleans engine state and releases ownership");

        engine.failTick = false;
        require(runtime.beginMove(replacement, false).startsWith("MOVE_STARTED "),
            "movement resumes after failed request");
        require(runtime.cancelMovement().startsWith("MOVE_CANCELLED "),
            "explicit interruption cancels request");
        require("IDLE".equals(runtime.tickMovement()),
            "interruption leaves no orphaned owner");
    }

    private static final class Target {
        private final int x;
        private final int y;
        private final int z;

        private Target(int x, int y, int z) {
            this.x = x;
            this.y = y;
            this.z = z;
        }
    }

    private static final class FakeMovementEngine implements KnoxNpcRuntime.MovementEngine {
        private int starts;
        private int cancels;
        private boolean failTick;
        private String tickResult = "Working";
        private boolean completeOnWrongFloor;
        private float x = 0.5f;
        private float y = 0.5f;
        private int z;
        private Target target;

        @Override
        public float bodyX(KnoxNpc npc) {
            return x;
        }

        @Override
        public float bodyY(KnoxNpc npc) {
            return y;
        }

        @Override
        public int bodyZ(KnoxNpc npc) {
            return z;
        }

        @Override
        public float targetX(Object square) {
            return ((Target) square).x + 0.5f;
        }

        @Override
        public float targetY(Object square) {
            return ((Target) square).y + 0.5f;
        }

        @Override
        public int targetZ(Object square) {
            return ((Target) square).z;
        }

        @Override
        public void start(KnoxNpc npc, Object square, boolean crossing) {
            starts++;
            target = (Target) square;
        }

        @Override
        public String tick(KnoxNpc npc, float remainingDistance, String pace)
            throws ReflectiveOperationException {
            if (failTick) {
                throw new ReflectiveOperationException("synthetic tick failure");
            }
            if ("Succeeded".equals(tickResult)) {
                x = target.x + 0.5f;
                y = target.y + 0.5f;
                if (!completeOnWrongFloor) {
                    z = target.z;
                }
            }
            return tickResult;
        }

        @Override
        public void cancel(KnoxNpc npc) {
            cancels++;
        }

    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new IllegalStateException(message);
        }
    }
}
