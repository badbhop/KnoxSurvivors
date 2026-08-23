package com.knoxsurvivors.bridge;

import com.knoxsurvivors.agent.KnoxAgent;
import com.knoxsurvivors.npc.KnoxNpcRegistry;

/**
 * Single Java object exposed to Project Zomboid Lua.
 *
 * <p>Gameplay capabilities will be added here only after each preceding bridge and lifecycle
 * milestone is verified in game.</p>
 */
public final class KnoxBridge {
    public static final String RUNTIME_VERSION = "0.0.1-dev";

    private long pingCount;
    private final KnoxNpcRegistry npcRegistry = new KnoxNpcRegistry();

    public synchronized String ping() {
        pingCount++;
        KnoxAgent.writeLog("Lua bridge ping count=" + pingCount);
        return "Knox Survivors Runtime " + RUNTIME_VERSION;
    }

    public String getRuntimeVersion() {
        return RUNTIME_VERSION;
    }

    public boolean isRuntimeLoaded() {
        return true;
    }

    public synchronized long getPingCount() {
        return pingCount;
    }

    public String spawnTestNpc(Object square) {
        return npcRegistry.spawnOne(square);
    }

    public String removeTestNpc() {
        return npcRegistry.removeOne();
    }

    public String moveTestNpc(Object square) {
        return npcRegistry.moveOne(square);
    }

    public String crossTestNpc(Object square) {
        return npcRegistry.crossOneAdjacentEdge(square);
    }

    public String tickTestNpc() {
        return npcRegistry.tickOne();
    }

    public String getTestNpcStatus() {
        return npcRegistry.status();
    }

    public boolean hasTestNpcTraversalEvidence(String state) {
        return npcRegistry.hasTraversalEvidence(state);
    }

    public String seedAndEquipTestNpc() {
        return npcRegistry.seedAndEquipOne();
    }

    public boolean isTestNpcFemale() {
        return npcRegistry.isOneFemale();
    }

    public String wearTestNpcItem(String fullType) {
        return npcRegistry.wearOneItem(fullType);
    }

    public String recreateTestNpc() {
        return npcRegistry.recreateOne();
    }

    public String getTestNpcEquipmentStatus() {
        return npcRegistry.equipmentStatus();
    }

    public String captureTestNpcRecord() {
        return npcRegistry.capturePersistentRecord();
    }

    public String restoreTestNpcRecord(String encoded, Object square) {
        return npcRegistry.restorePersistentRecord(encoded, square);
    }

    public int getTestNpcRecordX(String encoded) {
        return npcRegistry.persistentRecordX(encoded);
    }

    public int getTestNpcRecordY(String encoded) {
        return npcRegistry.persistentRecordY(encoded);
    }

    public int getTestNpcRecordZ(String encoded) {
        return npcRegistry.persistentRecordZ(encoded);
    }

    void abandonForEnvironmentChange() {
        npcRegistry.abandonForEnvironmentChange();
    }

    @Override
    public synchronized String toString() {
        return "KnoxBridge{version=" + RUNTIME_VERSION + ", pingCount=" + pingCount + "}";
    }
}
