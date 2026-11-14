package org.uwuapps.fixup.bridge;

import java.lang.annotation.ElementType;
import java.lang.annotation.Retention;
import java.lang.annotation.RetentionPolicy;
import java.lang.annotation.Target;

/** A plugin's name, as the Dart side calls it (Native.call(name, method, {...})), and the
 * permissions it asks for, each by an alias. */
@Retention(RetentionPolicy.RUNTIME)
@Target(ElementType.TYPE)
public @interface AppPlugin {
    String name();

    Permission[] permissions() default {};
}
