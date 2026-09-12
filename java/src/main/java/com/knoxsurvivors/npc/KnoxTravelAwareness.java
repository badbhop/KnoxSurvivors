package com.knoxsurvivors.npc;

/** Transient perception for one loaded body; never part of a save or movement owner. */
final class KnoxTravelAwareness {
    private static final long SCAN_INTERVAL_NANOS = 250_000_000L;
    private static final long CAUTION_HOLD_NANOS = 1_500_000_000L;
    record Observation(int visible, float nearestSquared, boolean detected) { }

    private boolean sampled;
    private long nextScan;
    private long cautiousUntil;
    private boolean hasCaution;
    private float x;
    private float y;
    private int z;
    private Observation observation = new Observation(0, Float.POSITIVE_INFINITY, false);

    boolean needsRefresh(long now, float currentX, float currentY, int currentZ) {
        float dx = currentX - x;
        float dy = currentY - y;
        return !sampled || now >= nextScan || currentZ != z || dx * dx + dy * dy > 16.0f;
    }

    void update(long now, float currentX, float currentY, int currentZ, Observation next) {
        float dx = currentX - x;
        float dy = currentY - y;
        if (!sampled || z != currentZ || dx * dx + dy * dy > 16.0f) hasCaution = false;
        sampled = true;
        nextScan = now + SCAN_INTERVAL_NANOS;
        x = currentX;
        y = currentY;
        z = currentZ;
        observation = next;
        if (next.detected() || next.nearestSquared() <= 4.0f) hasCaution = false;
        else if (next.visible() > 0) {
            hasCaution = true;
            cautiousUntil = now + CAUTION_HOLD_NANOS;
        }
    }

    boolean shouldSneak(long now, boolean cautiousPace, boolean orderedSneak) {
        if (!sampled || observation.detected() || observation.nearestSquared() <= 4.0f) return false;
        if (orderedSneak) return true;
        return cautiousPace ? hasCaution && now < cautiousUntil : observation.visible() >= 3;
    }
}
