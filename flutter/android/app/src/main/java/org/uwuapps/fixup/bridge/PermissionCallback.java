package org.uwuapps.fixup.bridge;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/** Where a permission request carries on, once Android's prompt is answered:
 * void name(PluginCall call), named to Plugin.requestPermissionForAlias. */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
public @interface PermissionCallback {
}
