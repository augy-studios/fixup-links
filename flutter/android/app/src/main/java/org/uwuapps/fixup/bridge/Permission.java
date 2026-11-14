package org.uwuapps.fixup.bridge;

import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;

/** One of a plugin's permissions: its alias, and the Android permissions it stands for. */
@Retention(RetentionPolicy.RUNTIME)
public @interface Permission {
    String alias();

    String[] strings();
}
