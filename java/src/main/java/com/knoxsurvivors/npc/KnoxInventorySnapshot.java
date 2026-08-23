package com.knoxsurvivors.npc;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collection;
import java.util.List;
import java.lang.reflect.Method;

/** Portable Knox-owned inventory state for rebuilding a temporary engine body. */
final class KnoxInventorySnapshot {
    static final int SCHEMA_VERSION = 1;

    private final List<ItemState> items;

    private KnoxInventorySnapshot(List<ItemState> items) {
        this.items = List.copyOf(items);
    }

    static KnoxInventorySnapshot capture(Object body) throws ReflectiveOperationException {
        Object inventory = invoke(body, "getInventory");
        Object wornItems = invoke(body, "getWornItems");
        Object primary = invoke(body, "getPrimaryHandItem");
        Object secondary = invoke(body, "getSecondaryHandItem");
        List<ItemState> states = new ArrayList<>();
        for (Object item : (Collection<?>) invoke(inventory, "getItems")) {
            states.add(new ItemState(
                (String) invoke(item, "getFullType"),
                ((Number) invoke(item, "getCondition")).intValue(),
                ((Number) invoke(item, "getUses")).intValue(),
                (Boolean) invoke(item, "isFavorite"),
                (Boolean) invokeCompatible(wornItems, "contains", item),
                item == primary,
                item == secondary
            ));
        }
        return new KnoxInventorySnapshot(states);
    }

    void restore(Object body) throws ReflectiveOperationException {
        Object inventory = invoke(body, "getInventory");
        Object wornItems = invoke(body, "getWornItems");
        invokeCompatible(body, "setPrimaryHandItem", (Object) null);
        invokeCompatible(body, "setSecondaryHandItem", (Object) null);
        invoke(wornItems, "clear");
        invoke(inventory, "clear");

        for (ItemState state : items) {
            Object item = inventory.getClass().getMethod("AddItem", String.class)
                .invoke(inventory, state.fullType);
            if (item == null) {
                throw new IllegalStateException("Unable to restore inventory item " + state.fullType);
            }
            item.getClass().getMethod("setCondition", int.class).invoke(item, state.condition);
            item.getClass().getMethod("setUses", int.class).invoke(item, state.uses);
            item.getClass().getMethod("setFavorite", boolean.class).invoke(item, state.favorite);
            Object bodyLocation = invoke(item, "getBodyLocation");
            if (state.worn && bodyLocation != null) {
                invokeCompatible(body, "setWornItem", bodyLocation, item);
            }
            if (state.primary) {
                invokeCompatible(body, "setPrimaryHandItem", item);
            }
            if (state.secondary) {
                invokeCompatible(body, "setSecondaryHandItem", item);
            }
        }

        inventory.getClass().getMethod("setDrawDirty", boolean.class).invoke(inventory, true);
        invoke(body, "resetModelNextFrame");
    }

    int size() {
        return items.size();
    }

    String primaryType() {
        for (ItemState item : items) {
            if (item.primary) {
                return item.fullType;
            }
        }
        return "none";
    }

    String encode() {
        StringBuilder encoded = new StringBuilder(Integer.toString(SCHEMA_VERSION));
        for (ItemState item : items) {
            encoded.append('\n')
                .append(text(item.fullType)).append('|')
                .append(item.condition).append('|')
                .append(item.uses).append('|')
                .append(item.favorite ? 1 : 0).append('|')
                .append(item.worn ? 1 : 0).append('|')
                .append(item.primary ? 1 : 0).append('|')
                .append(item.secondary ? 1 : 0);
        }
        return encoded.toString();
    }

    static KnoxInventorySnapshot decode(String encoded) {
        String[] lines = encoded.split("\\n", -1);
        if (lines.length == 0 || Integer.parseInt(lines[0]) != SCHEMA_VERSION) {
            throw new IllegalArgumentException("Unsupported inventory snapshot schema");
        }
        List<ItemState> states = new ArrayList<>();
        for (int index = 1; index < lines.length; index++) {
            String[] fields = lines[index].split("\\|", -1);
            if (fields.length != 7) {
                throw new IllegalArgumentException("Invalid inventory item record at " + index);
            }
            states.add(new ItemState(
                untext(fields[0]),
                Integer.parseInt(fields[1]),
                Integer.parseInt(fields[2]),
                "1".equals(fields[3]),
                "1".equals(fields[4]),
                "1".equals(fields[5]),
                "1".equals(fields[6])
            ));
        }
        return new KnoxInventorySnapshot(states);
    }

    private static String text(String value) {
        return Base64.getUrlEncoder().withoutPadding()
            .encodeToString(value.getBytes(StandardCharsets.UTF_8));
    }

    private static String untext(String value) {
        return new String(Base64.getUrlDecoder().decode(value), StandardCharsets.UTF_8);
    }

    private static Object invoke(Object target, String name) throws ReflectiveOperationException {
        return target.getClass().getMethod(name).invoke(target);
    }

    private static Object invokeCompatible(Object target, String name, Object... arguments)
        throws ReflectiveOperationException {
        for (Method method : target.getClass().getMethods()) {
            if (!method.getName().equals(name) || method.getParameterCount() != arguments.length) {
                continue;
            }
            Class<?>[] parameterTypes = method.getParameterTypes();
            boolean compatible = true;
            for (int index = 0; index < arguments.length; index++) {
                if (arguments[index] != null && !parameterTypes[index].isInstance(arguments[index])) {
                    compatible = false;
                    break;
                }
            }
            if (compatible) {
                return method.invoke(target, arguments);
            }
        }
        throw new NoSuchMethodException(target.getClass().getName() + "." + name);
    }

    private record ItemState(
        String fullType,
        int condition,
        int uses,
        boolean favorite,
        boolean worn,
        boolean primary,
        boolean secondary
    ) {
    }
}
