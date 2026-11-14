package org.uwuapps.fixup.bridge;

import org.json.JSONArray;
import org.json.JSONException;

import java.util.Collection;

/** A JSON array to and from the Dart side: org.json's, as the plugins have always used it. */
public class JSArray extends JSONArray {

    public JSArray() {
        super();
    }

    public JSArray(Collection<?> items) {
        super(items);
    }

    public JSArray(String json) throws JSONException {
        super(json);
    }

    /** A copy of any JSONArray as a JSArray, or null for null. */
    public static JSArray from(JSONArray a) {
        if (a == null) return null;
        if (a instanceof JSArray) return (JSArray) a;
        JSArray out = new JSArray();
        for (int i = 0; i < a.length(); i++) out.put(a.opt(i));
        return out;
    }
}
