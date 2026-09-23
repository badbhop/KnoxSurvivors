package com.knoxsurvivors;

import com.knoxsurvivors.agent.KnoxAgent;

/**
 * ZombieBuddy Java-mod entry point.
 *
 * <p>ZombieBuddy loads this class from Knox Survivors' JAR and invokes main(String[]).
 * Knox then reuses ZombieBuddy's Instrumentation handle instead of requiring its own
 * -javaagent launch option.</p>
 */
public final class Main {
    private Main() {
    }

    public static void main(String[] args) {
        KnoxAgent.startFromZombieBuddy();
    }
}
