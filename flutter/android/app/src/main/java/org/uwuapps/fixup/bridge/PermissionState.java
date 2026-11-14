package org.uwuapps.fixup.bridge;

/** An Android permission's state, as the Dart side sees it: "granted", "denied", "prompt", or
 * "prompt-with-rationale" (asked before, and Android would show why it's wanted). "denied" is
 * refused for good: Android won't ask again, and only the app's settings can allow it. */
public enum PermissionState {
    GRANTED("granted"),
    DENIED("denied"),
    PROMPT("prompt"),
    PROMPT_WITH_RATIONALE("prompt-with-rationale");

    private final String state;

    PermissionState(String state) {
        this.state = state;
    }

    @Override
    public String toString() {
        return state;
    }
}
