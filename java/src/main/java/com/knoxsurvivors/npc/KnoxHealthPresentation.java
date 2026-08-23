package com.knoxsurvivors.npc;

import java.lang.reflect.Method;
import java.util.Collection;

/** Rebuilds engine wound, blood, and bandage visuals from persistent BodyDamage state. */
final class KnoxHealthPresentation {
    private static final String BASE_MODULE = "Base.";

    private KnoxHealthPresentation() {
    }

    static String refresh(Object body) throws ReflectiveOperationException {
        Object damage = body.getClass().getMethod("getBodyDamage").invoke(body);
        Object visual = body.getClass().getMethod("getVisual").invoke(body);
        Object gender = body.getClass().getMethod("getCharacterGender").invoke(body);
        Object parts = damage.getClass().getMethod("getBodyParts").invoke(damage);
        ClassLoader loader = body.getClass().getClassLoader();
        Class<?> bloodType = Class.forName(
            "zombie.characterTextures.BloodBodyPartType",
            false,
            loader
        );
        Method bloodFromIndex = bloodType.getMethod("FromIndex", int.class);
        Method addBlood = body.getClass().getMethod(
            "addBlood",
            bloodType,
            boolean.class,
            boolean.class,
            boolean.class
        );

        int woundsAdded = 0;
        int bandagesAdded = 0;
        int bloodParts = 0;
        for (Object part : (Collection<?>) parts) {
            Object type = part.getClass().getMethod("getType").invoke(part);
            int index = ((Number) part.getClass().getMethod("getIndex").invoke(part)).intValue();

            boolean injured = (Boolean) part.getClass().getMethod("HasInjury").invoke(part);
            boolean bleeding = (Boolean) part.getClass().getMethod("bleeding").invoke(part);
            boolean bandaged = (Boolean) part.getClass().getMethod("bandaged").invoke(part);
            if (injured || bleeding) {
                Object bloodPart = bloodFromIndex.invoke(null, index);
                addBlood.invoke(body, bloodPart, true, false, true);
                bloodParts++;
            }

            String woundModel = woundModel(part, type, gender);
            reconcileWoundModels(visual, type, gender, woundModel);
            if (woundModel != null && addVisualIfMissing(visual, woundModel)) {
                woundsAdded++;
            }
            String bandageBase = (String) type.getClass().getMethod("getBandageModel")
                .invoke(type);
            boolean dirty = (Boolean) part.getClass().getMethod("isBandageDirty")
                .invoke(part);
            String bandageModel = bandaged && bandageBase != null
                ? bandageBase + (dirty ? "_Blood" : "")
                : null;
            reconcileBandageModels(visual, bandageBase, bandageModel);
            if (bandageModel != null && addVisualIfMissing(visual, bandageModel)) {
                    bandagesAdded++;
            }
        }
        body.getClass().getMethod("resetModelNextFrame").invoke(body);
        int bodyVisuals = ((Collection<?>) visual.getClass().getMethod("getBodyVisuals")
            .invoke(visual)).size();
        return "HEALTH_PRESENTATION bloodParts=" + bloodParts
            + " woundsAdded=" + woundsAdded
            + " bandagesAdded=" + bandagesAdded
            + " bodyVisuals=" + bodyVisuals;
    }

    private static String woundModel(Object part, Object type, Object gender)
        throws ReflectiveOperationException {
        if ((Boolean) part.getClass().getMethod("bitten").invoke(part)) {
            return (String) type.getClass().getMethod(
                "getBiteWoundModel",
                gender.getClass()
            ).invoke(type, gender);
        }
        if ((Boolean) part.getClass().getMethod("isCut").invoke(part)) {
            return (String) type.getClass().getMethod(
                "getCutWoundModel",
                gender.getClass()
            ).invoke(type, gender);
        }
        if ((Boolean) part.getClass().getMethod("scratched").invoke(part)) {
            return (String) type.getClass().getMethod(
                "getScratchWoundModel",
                gender.getClass()
            ).invoke(type, gender);
        }
        return null;
    }

    private static boolean addVisualIfMissing(Object visual, String model)
        throws ReflectiveOperationException {
        if (model == null || model.isBlank()) {
            return false;
        }
        String fullType = fullType(model);
        Method hasVisual = visual.getClass().getMethod("hasBodyVisualFromItemType", String.class);
        if ((Boolean) hasVisual.invoke(visual, fullType)) {
            return false;
        }
        Object added = visual.getClass().getMethod("addBodyVisualFromItemType", String.class)
            .invoke(visual, fullType);
        return added != null;
    }

    private static void reconcileWoundModels(
        Object visual,
        Object type,
        Object gender,
        String activeModel
    ) throws ReflectiveOperationException {
        removeUnlessActive(visual, woundModel(type, gender, "getBiteWoundModel"), activeModel);
        removeUnlessActive(visual, woundModel(type, gender, "getScratchWoundModel"), activeModel);
        removeUnlessActive(visual, woundModel(type, gender, "getCutWoundModel"), activeModel);
    }

    private static void reconcileBandageModels(Object visual, String baseModel, String activeModel)
        throws ReflectiveOperationException {
        removeUnlessActive(visual, baseModel, activeModel);
        removeUnlessActive(
            visual,
            baseModel == null ? null : baseModel + "_Blood",
            activeModel
        );
    }

    private static String woundModel(Object type, Object gender, String method)
        throws ReflectiveOperationException {
        return (String) type.getClass().getMethod(method, gender.getClass()).invoke(type, gender);
    }

    private static void removeUnlessActive(Object visual, String candidate, String active)
        throws ReflectiveOperationException {
        if (candidate == null || candidate.equals(active)) {
            return;
        }
        String fullType = fullType(candidate);
        Method hasVisual = visual.getClass().getMethod("hasBodyVisualFromItemType", String.class);
        if ((Boolean) hasVisual.invoke(visual, fullType)) {
            visual.getClass().getMethod("removeBodyVisualFromItemType", String.class)
                .invoke(visual, fullType);
        }
    }

    private static String fullType(String model) {
        return model.indexOf('.') >= 0 ? model : BASE_MODULE + model;
    }
}
