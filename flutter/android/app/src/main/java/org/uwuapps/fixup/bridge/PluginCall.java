package org.uwuapps.fixup.bridge;

import org.json.JSONArray;
import org.json.JSONObject;

/**
 * One call from the Dart side to a plugin's method, with its options (getData()), answered once by
 * resolve() or reject(). The Dart future completes with the first answer; a call kept alive
 * (setKeepAlive) is kept by the plugin to answer later, after Android has.
 */
public class PluginCall {

    /** Where the answer goes: Bridge, back to the Dart side. */
    interface Answer {
        void resolve(JSObject data);

        void reject(String message, String code, JSObject data);
    }

    private final String pluginId;
    private final String methodName;
    private final JSObject data;
    private final Answer answer;
    private boolean keepAlive;
    private volatile boolean answered;

    PluginCall(String pluginId, String methodName, JSObject data, Answer answer) {
        this.pluginId = pluginId;
        this.methodName = methodName;
        this.data = data == null ? new JSObject() : data;
        this.answer = answer;
    }

    public String getPluginId() {
        return pluginId;
    }

    public String getMethodName() {
        return methodName;
    }

    /** The call's options, which a plugin may add to between its permission steps. */
    public JSObject getData() {
        return data;
    }

    public boolean hasOption(String name) {
        return data.has(name);
    }

    public String getString(String name) {
        return data.getString(name, null);
    }

    public String getString(String name, String fallback) {
        return data.getString(name, fallback);
    }

    public Integer getInt(String name) {
        return data.getInteger(name, null);
    }

    public Integer getInt(String name, Integer fallback) {
        return data.getInteger(name, fallback);
    }

    public Long getLong(String name, Long fallback) {
        Object v = data.opt(name);
        return v instanceof Number ? Long.valueOf(((Number) v).longValue()) : fallback;
    }

    public Double getDouble(String name, Double fallback) {
        Object v = data.opt(name);
        return v instanceof Number ? Double.valueOf(((Number) v).doubleValue()) : fallback;
    }

    public Boolean getBoolean(String name) {
        return data.getBoolean(name, null);
    }

    public Boolean getBoolean(String name, Boolean fallback) {
        return data.getBoolean(name, fallback);
    }

    public JSObject getObject(String name) {
        return getObject(name, null);
    }

    public JSObject getObject(String name, JSObject fallback) {
        Object v = data.opt(name);
        return v instanceof JSONObject ? JSObject.from((JSONObject) v) : fallback;
    }

    public JSArray getArray(String name) {
        return getArray(name, null);
    }

    public JSArray getArray(String name, JSArray fallback) {
        Object v = data.opt(name);
        return v instanceof JSONArray ? JSArray.from((JSONArray) v) : fallback;
    }

    /** Kept to answer later, rather than finished with the plugin method's return. */
    public void setKeepAlive(boolean keep) {
        keepAlive = keep;
    }

    public boolean isKeptAlive() {
        return keepAlive;
    }

    public boolean isAnswered() {
        return answered;
    }

    public void resolve() {
        resolve(null);
    }

    public void resolve(JSObject result) {
        if (answered) return;
        answered = true;
        answer.resolve(result);
    }

    public void reject(String message) {
        reject(message, null, null, null);
    }

    public void reject(String message, String code) {
        reject(message, code, null, null);
    }

    public void reject(String message, Exception e) {
        reject(message, null, e, null);
    }

    public void reject(String message, String code, Exception e) {
        reject(message, code, e, null);
    }

    /** The Dart future fails with a NativeError of this message, with its code and data. */
    public void reject(String message, String code, Exception e, JSObject data) {
        if (answered) return;
        answered = true;
        if (e != null) android.util.Log.w("Fixup", pluginId + "." + methodName + ": " + message, e);
        answer.reject(message, code, data);
    }
}
