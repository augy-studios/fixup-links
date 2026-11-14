package org.uwuapps.fixup.bridge;

import org.json.JSONException;
import org.json.JSONObject;

import java.util.Iterator;

/**
 * A JSON object to and from the Dart side: org.json's, with put() that never throws and getters that
 * answer a default, as the plugins have always used them (they were Capacitor's).
 */
public class JSObject extends JSONObject {

    public JSObject() {
        super();
    }

    public JSObject(String json) throws JSONException {
        super(json);
    }

    /** A copy of any JSONObject as a JSObject, or null for null. */
    public static JSObject from(JSONObject o) {
        if (o == null) return null;
        if (o instanceof JSObject) return (JSObject) o;
        JSObject out = new JSObject();
        for (Iterator<String> keys = o.keys(); keys.hasNext(); ) {
            String k = keys.next();
            out.put(k, o.opt(k));
        }
        return out;
    }

    /** The string at name, or null if there's none (or it isn't a string). */
    @Override
    public String getString(String name) {
        return getString(name, null);
    }

    public String getString(String name, String fallback) {
        Object v = opt(name);
        return v instanceof String ? (String) v : fallback;
    }

    public Integer getInteger(String name) {
        return getInteger(name, null);
    }

    public Integer getInteger(String name, Integer fallback) {
        Object v = opt(name);
        return v instanceof Number ? Integer.valueOf(((Number) v).intValue()) : fallback;
    }

    public Boolean getBoolean(String name, Boolean fallback) {
        Object v = opt(name);
        return v instanceof Boolean ? (Boolean) v : fallback;
    }

    public JSObject getJSObject(String name) {
        Object v = opt(name);
        return v instanceof JSONObject ? from((JSONObject) v) : null;
    }

    @Override
    public JSObject put(String key, boolean value) {
        try {
            super.put(key, value);
        } catch (JSONException ignored) {
            // A null key: nothing put.
        }
        return this;
    }

    @Override
    public JSObject put(String key, int value) {
        try {
            super.put(key, value);
        } catch (JSONException ignored) {
            // A null key: nothing put.
        }
        return this;
    }

    @Override
    public JSObject put(String key, long value) {
        try {
            super.put(key, value);
        } catch (JSONException ignored) {
            // A null key: nothing put.
        }
        return this;
    }

    @Override
    public JSObject put(String key, double value) {
        try {
            super.put(key, value);
        } catch (JSONException ignored) {
            // NaN or infinite, which JSON can't hold: nothing put.
        }
        return this;
    }

    /** A null string is put as JSON's null, so Dart sees the key with null. */
    public JSObject put(String key, String value) {
        try {
            super.put(key, value == null ? JSONObject.NULL : value);
        } catch (JSONException ignored) {
            // A null key: nothing put.
        }
        return this;
    }

    @Override
    public JSObject put(String key, Object value) {
        try {
            super.put(key, value == null ? JSONObject.NULL : value);
        } catch (JSONException ignored) {
            // A null key, or a number JSON can't hold: nothing put.
        }
        return this;
    }
}
