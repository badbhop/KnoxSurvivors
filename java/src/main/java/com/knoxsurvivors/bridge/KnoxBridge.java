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

    public String spawnNpc(String id, Object square) {
        return npcRegistry.spawn(id, square);
    }

    public String removeTestNpc() {
        return npcRegistry.removeOne();
    }

    public String removeNpc(String id) {
        return npcRegistry.remove(id);
    }

    public String moveTestNpc(Object square) {
        return npcRegistry.moveOne(square);
    }

    public String moveNpc(String id, Object square) {
        return npcRegistry.move(id, square);
    }

    public String moveNpcWithPace(String id, Object square, String pace) {
        return npcRegistry.moveWithPace(id, square, pace);
    }

    public String crossTestNpc(Object square) {
        return npcRegistry.crossOneAdjacentEdge(square);
    }

    public String crossNpc(String id, Object square) {
        return npcRegistry.cross(id, square);
    }

    public String tickTestNpc() {
        return npcRegistry.tickOne();
    }

    public String tickNpc(String id) {
        return npcRegistry.tick(id);
    }

    public String cancelNpcMove(String id) {
        return npcRegistry.cancelMove(id);
    }

    public boolean setNpcClimbingAllowed(String id, boolean allowed) {
        return npcRegistry.setClimbingAllowed(id, allowed);
    }

    public boolean setNpcProtectedArea(String id, int minX, int minY, int maxX, int maxY) {
        return npcRegistry.setProtectedArea(id, minX, minY, maxX, maxY);
    }

    public boolean clearNpcProtectedArea(String id) {
        return npcRegistry.clearProtectedArea(id);
    }

    public String getTestNpcStatus() {
        return npcRegistry.status();
    }

    public String getNpcStatus(String id) {
        return npcRegistry.status(id);
    }

    public int getActiveNpcCount() {
        return npcRegistry.activeCount();
    }

    public String getActiveNpcIds() {
        return npcRegistry.activeIds();
    }

    public String getRenderDiagnostics() {
        return npcRegistry.renderDiagnostics();
    }

    public boolean hasTestNpcTraversalEvidence(String state) {
        return npcRegistry.hasTraversalEvidence(state);
    }

    public String seedAndEquipTestNpc() {
        return npcRegistry.seedAndEquipOne();
    }

    public String seedAndEquipNpc(String id) {
        return npcRegistry.seedAndEquip(id);
    }

    public String equipBestNpc(String id) {
        return npcRegistry.equipBest(id);
    }

    public boolean isTestNpcFemale() {
        return npcRegistry.isOneFemale();
    }

    public boolean isNpcFemale(String id) {
        return npcRegistry.isFemale(id);
    }

    public String wearTestNpcItem(String fullType) {
        return npcRegistry.wearOneItem(fullType);
    }

    public String wearNpcItem(String id, String fullType) {
        return npcRegistry.wearItem(id, fullType);
    }

    public String dressNpcItem(String id, String fullType) {
        return npcRegistry.dressItem(id, fullType);
    }

    public String recreateTestNpc() {
        return npcRegistry.recreateOne();
    }

    public String getTestNpcEquipmentStatus() {
        return npcRegistry.equipmentStatus();
    }

    public String beginTestNpcCombat(Object zombie, Object approachSquare) {
        return npcRegistry.beginCombatOne(zombie, approachSquare);
    }

    public String beginTestNpcLiveCombat(Object zombie, Object approachSquare) {
        return npcRegistry.beginLiveCombatOne(zombie, approachSquare);
    }

    public void resetTestNpcCombat() {
        npcRegistry.resetCombatOne();
    }

    public String tickTestNpcCombat() {
        return npcRegistry.tickCombatOne();
    }

    public Object getTestNpcCharacterForAction() {
        return npcRegistry.activeCharacterForAction();
    }

    public Object getNpcCharacter(String id) {
        return npcRegistry.character(id);
    }

    public String prepareTestNpcHealthGate() {
        return npcRegistry.prepareHealthGateOne();
    }

    public float getTestNpcHealth() {
        return npcRegistry.healthOne();
    }

    public String refreshTestNpcHealthPresentation() {
        return npcRegistry.refreshHealthPresentationOne();
    }

    public int getTestNpcInjuredPartCount() {
        return npcRegistry.injuredPartsOne();
    }

    public int getTestNpcBleedingPartCount() {
        return npcRegistry.bleedingPartsOne();
    }

    public String normalizeTestNpcMinorInjury() {
        return npcRegistry.normalizeMinorInjuryOne();
    }

    public String directTestZombieAtNpc(Object zombie) {
        return npcRegistry.directZombieAtOne(zombie);
    }

    public String directZombieAtNpc(String id, Object zombie) {
        return npcRegistry.directZombieAt(id, zombie);
    }

    public String getZombieAttackDiagnostics(String id, Object zombie) {
        return npcRegistry.zombieAttackDiagnostics(id, zombie);
    }

    public String getNpcCombatDiagnostics(String id) {
        return npcRegistry.combatDiagnostics(id);
    }

    public String captureTestNpcRecord() {
        return npcRegistry.capturePersistentRecord();
    }

    public String captureNpcRecord(String id) {
        return npcRegistry.capturePersistentRecord(id);
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

    public String getNpcRecordId(String encoded) {
        return npcRegistry.persistentRecordId(encoded);
    }

    /** Read-only inventory counts from a portable stored survivor record. */
    public String getNpcRecordInventorySummary(String encoded) {
        return npcRegistry.persistentRecordInventorySummary(encoded);
    }

    /** Consumes one real stored item without reconstructing the survivor body. */
    public String consumeNpcRecordItem(String encoded, String fullType) {
        return npcRegistry.consumePersistentRecordItem(encoded, fullType);
    }

    public String beginNpcLiveCombat(String id, Object zombie, Object approachSquare) {
        return npcRegistry.beginLiveCombat(id, zombie, approachSquare);
    }

    public String beginNpcLockedDoorCombat(String id) {
        return npcRegistry.beginLockedDoorCombat(id);
    }

    public String tickNpcCombat(String id) {
        return npcRegistry.tickCombat(id);
    }

    public void resetNpcCombat(String id) {
        npcRegistry.resetCombat(id);
    }

    void abandonForEnvironmentChange() {
        npcRegistry.abandonForEnvironmentChange();
    }

    @Override
    public synchronized String toString() {
        return "KnoxBridge{version=" + RUNTIME_VERSION + ", pingCount=" + pingCount + "}";
    }
}
