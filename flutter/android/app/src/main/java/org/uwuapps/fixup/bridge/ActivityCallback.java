package org.uwuapps.fixup.bridge;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/** Where Plugin.startActivityForResult carries on, with the activity's result:
 * void name(PluginCall call, ActivityResult result). */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
public @interface ActivityCallback {
}
