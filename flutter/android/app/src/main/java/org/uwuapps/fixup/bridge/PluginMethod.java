package org.uwuapps.fixup.bridge;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/** A method the Dart side may call: public void name(PluginCall call). */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.METHOD)
public @interface PluginMethod {
}
