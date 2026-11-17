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
    public static JSObject from(JSONObject source) {
        if (source == null) {
            return null;
        }
        if (source instanceof JSObject) {
            return (JSObject) source;
        }
        JSObject copy = new JSObject();
        for (Iterator<String> keys = source.keys(); keys.hasNext(); ) {
            String key = keys.next();
            copy.put(key, source.opt(key));
        }
        return copy;
    }

    /** The string at name, or null if there's none (or it isn't a string). */
    @Override
    public String getString(String name) {
        return getString(name, null);
    }

    public String getString(String name, String fallback) {
        Object value = opt(name);
        if (value instanceof String) {
            return (String) value;
        }
        return fallback;
    }

    public Integer getInteger(String name) {
        return getInteger(name, null);
    }

    public Integer getInteger(String name, Integer fallback) {
        Object value = opt(name);
        if (value instanceof Number) {
            return Integer.valueOf(((Number) value).intValue());
        }
        return fallback;
    }

    public Boolean getBoolean(String name, Boolean fallback) {
        Object value = opt(name);
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        return fallback;
    }

    public JSObject getJSObject(String name) {
        Object value = opt(name);
        if (value instanceof JSONObject) {
            return from((JSONObject) value);
        }
        return null;
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
            if (value == null) {
                super.put(key, JSONObject.NULL);
            } else {
                super.put(key, value);
            }
        } catch (JSONException ignored) {
            // A null key: nothing put.
        }
        return this;
    }

    @Override
    public JSObject put(String key, Object value) {
        try {
            if (value == null) {
                super.put(key, JSONObject.NULL);
            } else {
                super.put(key, value);
            }
        } catch (JSONException ignored) {
            // A null key, or a number JSON can't hold: nothing put.
        }
        return this;
    }
}
