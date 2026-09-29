package com.knoxsurvivors;

import com.knoxsurvivors.agent.KnoxAgent;
import com.knoxbridge.api.KnoxModule;
import com.knoxbridge.api.ModuleContext;

/** KnoxBridge module entry point for the existing Knox Java runtime. */
public final class Main implements KnoxModule {
    public Main() { }

    @Override
    public void initialize(ModuleContext context) {
        context.logger().accept("Knox module init start runtime=" + context.runtimeVersion());
        KnoxAgent.startFromKnoxBridge(context.instrumentation());
    }
}
