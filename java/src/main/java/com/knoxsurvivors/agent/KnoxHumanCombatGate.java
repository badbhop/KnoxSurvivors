package com.knoxsurvivors.agent;

import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.util.IdentityHashMap;

/** Eligibility only: native hit, damage, ammunition and animation code is untouched. */
public final class KnoxHumanCombatGate {
    private static final String SHELL = "com.knoxsurvivors.engine.KnoxIsoPlayerShell";
    private static final Pairs PAIRS = new Pairs();
    private static final PlayerAttacks PLAYER_ATTACKS = new PlayerAttacks();
    private static final ClassValue<Api> API = new ClassValue<>() {
        @Override protected Api computeValue(Class<?> type) {
            try {
                ClassLoader loader = type.getClassLoader();
                Class<?> moving = Class.forName("zombie.iso.IsoMovingObject", false, loader);
                Class<?> player = Class.forName("zombie.characters.IsoPlayer", false, loader);
                return new Api(
                    Class.forName("zombie.CombatManager", false, loader).getMethod("checkPVP", moving, moving, boolean.class),
                    Class.forName("zombie.network.GameClient", false, loader).getField("client"),
                    Class.forName("zombie.network.GameServer", false, loader).getField("server"),
                    player, player.getMethod("isGodMod"), player.getMethod("isDead"),
                    player.getMethod("getCurrentSquare"), player.getMethod("isLocalPlayer"));
            } catch (ReflectiveOperationException exception) {
                throw new IllegalStateException("Native human combat API unavailable", exception);
            }
        }
    };

    private KnoxHumanCombatGate() { }

    /** Called only by the existing live combat owner after target acceptance. */
    public static void refresh(Object owner, Object body, Object target) {
        if (body != null && SHELL.equals(body.getClass().getName()) && body != target) {
            PAIRS.put(owner, body, target, System.nanoTime());
        } else PAIRS.remove(owner);
    }

    public static void clear(Object owner) { PAIRS.remove(owner); }

    public static void clearPlayerAttacks() { PLAYER_ATTACKS.clear(); }

    public static boolean beginPlayerAttack(Object player) {
        if (player == null || SHELL.equals(player.getClass().getName())) return false;
        try {
            Api api = API.get(player.getClass());
            if (!api.player.isInstance(player) || !(Boolean) api.local.invoke(player)
                || (Boolean) api.client.get(null) || (Boolean) api.server.get(null)) return false;
            PLAYER_ATTACKS.begin(player, System.nanoTime());
            return true;
        } catch (ReflectiveOperationException | RuntimeException exception) { return false; }
    }

    public static void setPlayerAttackTarget(Object player, Object body, boolean allowed) {
        if (body != null && SHELL.equals(body.getClass().getName()))
            PLAYER_ATTACKS.set(player, body, allowed, System.nanoTime());
    }

    public static boolean checkPVP(Object attacker, Object victim, boolean checkFaction) {
        Object anchor = attacker != null ? attacker : victim;
        if (anchor == null) return true; // Native checkPVP(null, null) permits non-player objects.
        try {
            Api api = API.get(anchor.getClass());
            boolean client = (Boolean) api.client.get(null), server = (Boolean) api.server.get(null);
            Boolean playerPermission = PLAYER_ATTACKS.permission(attacker, victim, System.nanoTime());
            if (!client && !server && playerPermission != null) {
                return playerPermission && canHit((Boolean) api.god.invoke(victim),
                    (Boolean) api.dead.invoke(attacker), (Boolean) api.dead.invoke(victim),
                    api.square.invoke(attacker) != null, api.square.invoke(victim) != null);
            }
            boolean paired = PAIRS.contains(attacker, victim, System.nanoTime());
            if (usesPair(paired, client, server,
                api.player.isInstance(attacker), api.player.isInstance(victim))) {
                return canHit((Boolean) api.god.invoke(victim),
                    (Boolean) api.dead.invoke(attacker), (Boolean) api.dead.invoke(victim),
                    api.square.invoke(attacker) != null, api.square.invoke(victim) != null);
            }
            // Original method is not patched: all unrelated and multiplayer checks remain native.
            return (Boolean) api.original.invoke(null, attacker, victim, checkFaction);
        } catch (ReflectiveOperationException | RuntimeException exception) {
            return false;
        }
    }

    static boolean usesPair(boolean paired, boolean client, boolean server, boolean humanA, boolean humanB) {
        return paired && !client && !server && humanA && humanB;
    }

    static boolean canHit(boolean god, boolean deadA, boolean deadB, boolean loadedA, boolean loadedB) {
        return !god && !deadA && !deadB && loadedA && loadedB;
    }

    private record Api(Method original, Field client, Field server, Class<?> player,
                       Method god, Method dead, Method square, Method local) { }

    /** Refreshed at native swing/hit-point events; never authorizes the reverse direction. */
    static final class PlayerAttacks {
        static final long TTL = 1_000_000_000L;
        private final IdentityHashMap<Object, Attack> attacks = new IdentityHashMap<>();
        synchronized void begin(Object player, long now) {
            prune(now);
            if (player != null) attacks.put(player, new Attack(now));
        }
        synchronized void set(Object player, Object victim, boolean allowed, long now) {
            prune(now);
            Attack attack = attacks.get(player);
            if (attack != null && victim != null && victim != player) attack.targets.put(victim, allowed);
        }
        synchronized Boolean permission(Object player, Object victim, long now) {
            prune(now);
            Attack attack = attacks.get(player);
            return attack == null ? null : attack.targets.get(victim);
        }
        synchronized void clear() { attacks.clear(); }
        private void prune(long now) { attacks.values().removeIf(attack -> now - attack.time >= TTL); }
        private static final class Attack {
            final long time;
            final IdentityHashMap<Object, Boolean> targets = new IdentityHashMap<>();
            Attack(long time) { this.time = time; }
        }
    }

    /** Short lease prevents a missed cleanup from granting indefinite attack permission. */
    static final class Pairs {
        static final long TTL = 5_000_000_000L;
        private final IdentityHashMap<Object, Pair> pairs = new IdentityHashMap<>();
        synchronized void put(Object owner, Object body, Object target, long now) {
            prune(now);
            if (owner == null) return;
            if (body == null || target == null || body == target) { pairs.remove(owner); return; }
            Pair current = pairs.get(owner);
            if (current != null && current.body == body && current.target == target) current.time = now;
            else pairs.put(owner, new Pair(body, target, now));
        }
        synchronized void remove(Object owner) { pairs.remove(owner); }
        synchronized boolean contains(Object a, Object b, long now) {
            prune(now);
            for (Pair pair : pairs.values()) {
                // The attacked human can defend itself, but no third-party bystander is authorized.
                if ((pair.body == a && pair.target == b) || (pair.body == b && pair.target == a)) return true;
            }
            return false;
        }
        private void prune(long now) { pairs.values().removeIf(pair -> now - pair.time >= TTL); }
        private static final class Pair {
            final Object body, target;
            long time;
            Pair(Object body, Object target, long time) { this.body = body; this.target = target; this.time = time; }
        }
    }
}
