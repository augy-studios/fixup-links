package org.uwuapps.fixup.bridge;

import android.content.Context;
import android.content.Intent;
import android.net.Uri;

import androidx.appcompat.app.AppCompatActivity;

import java.util.LinkedHashMap;
import java.util.Map;

/**
 * One of the app's plugins, as the Dart side reaches it (android/lib/native/native_bridge.dart):
 * Native.call(name, method, {...}) calls its @PluginMethod of that name, and
 * Native.on(name, event, fn) hears its notifyListeners(event, ...). Named, with its
 * permissions, by @AppPlugin, and registered in MainActivity.onCreate.
 *
 * Every plugin can also be asked checkPermissions(), { alias: state } for each of its
 * permissions, and requestPermissions({ permissions: [alias, ...] }), Android's prompt for those
 * (all of them without), answering the same.
 *
 * Plugin methods run on the bridge's own thread, never the main one: what has to be on the main
 * thread goes through getActivity().runOnUiThread. Permission and activity callbacks come on the
 * main thread.
 */
public abstract class Plugin {

    protected Bridge bridge;
    private String name;
    private Permission[] permissions = new Permission[0];

    final void init(Bridge bridge, String name, Permission[] permissions) {
        this.bridge = bridge;
        this.name = name;
        if (permissions == null) {
            this.permissions = new Permission[0];
        } else {
            this.permissions = permissions;
        }
    }

    /** Called once, as the plugin's registered, while the activity's being created. */
    public void load() {
    }

    public String getName() {
        return name;
    }

    public Bridge getBridge() {
        return bridge;
    }

    public Context getContext() {
        return bridge.getContext();
    }

    public AppCompatActivity getActivity() {
        return bridge.getActivity();
    }

    // ---------- events to the Dart side ----------

    protected void notifyListeners(String event, JSObject data) {
        notifyListeners(event, data, false);
    }

    /**
     * An event for the Dart side's listeners. With retain, one that comes while nothing listens
     * is kept and handed to the first listener added, as a card held to the phone before the
     * app's screens are up is.
     */
    protected void notifyListeners(String event, JSObject data, boolean retain) {
        bridge.emit(this, event, data, retain);
    }

    protected boolean hasListeners(String event) {
        return bridge.isListening(name, event);
    }

    // ---------- permissions ----------

    Permission[] permissions() {
        return permissions;
    }

    Permission permission(String alias) {
        for (Permission permission : permissions) {
            if (permission.alias().equals(alias)) {
                return permission;
            }
        }
        return null;
    }

    public PermissionState getPermissionState(String alias) {
        Permission permission = permission(alias);
        if (permission == null) {
            return PermissionState.DENIED;
        }
        return bridge.permissionState(permission.strings());
    }

    public Map<String, PermissionState> getPermissionStates() {
        Map<String, PermissionState> states = new LinkedHashMap<>();
        for (Permission permission : permissions) {
            states.put(permission.alias(), bridge.permissionState(permission.strings()));
        }
        return states;
    }

    /** Android's prompt for one alias's permissions, then callbackName(call), a @PermissionCallback. */
    protected void requestPermissionForAlias(String alias, PluginCall call, String callbackName) {
        requestPermissionForAliases(new String[]{alias}, call, callbackName);
    }

    protected void requestPermissionForAliases(String[] aliases, PluginCall call, String callbackName) {
        java.util.List<String> strings = new java.util.ArrayList<>();
        for (String alias : aliases) {
            Permission permission = permission(alias);
            if (permission != null) {
                java.util.Collections.addAll(strings, permission.strings());
            }
        }
        bridge.requestPermissions(this, strings.toArray(new String[0]), call, callbackName);
    }

    protected void requestAllPermissions(PluginCall call, String callbackName) {
        requestPermissionForAliases(allAliases(), call, callbackName);
    }

    /** The alias of every one of this plugin's permissions, in the order @AppPlugin lists them. */
    private String[] allAliases() {
        String[] aliases = new String[permissions.length];
        for (int index = 0; index < permissions.length; index++) {
            aliases[index] = permissions[index].alias();
        }
        return aliases;
    }

    @PluginMethod
    public void checkPermissions(PluginCall call) {
        call.resolve(states());
    }

    @PluginMethod
    public void requestPermissions(PluginCall call) {
        JSArray asked = call.getArray("permissions");
        String[] aliases;
        if (asked == null || asked.length() == 0) {
            aliases = allAliases();
        } else {
            aliases = new String[asked.length()];
            for (int index = 0; index < asked.length(); index++) {
                aliases[index] = asked.optString(index);
            }
        }
        requestPermissionForAliases(aliases, call, "afterRequestPermissions");
    }

    @PermissionCallback
    private void afterRequestPermissions(PluginCall call) {
        call.resolve(states());
    }

    private JSObject states() {
        JSObject states = new JSObject();
        for (Map.Entry<String, PermissionState> entry : getPermissionStates().entrySet()) {
            states.put(entry.getKey(), entry.getValue().toString());
        }
        return states;
    }

    // ---------- other activities ----------

    /** Starts intent for its result, then callbackName(call, result), an @ActivityCallback. */
    protected void startActivityForResult(PluginCall call, Intent intent, String callbackName) {
        bridge.startActivityForResult(this, call, intent, callbackName);
    }

    // ---------- the activity's lifecycle, and links off the site ----------

    protected void handleOnStart() {
    }

    protected void handleOnResume() {
    }

    protected void handleOnPause() {
    }

    protected void handleOnStop() {
    }

    protected void handleOnDestroy() {
    }

    protected void handleOnNewIntent(Intent intent) {
    }

    /** Asked of every plugin for each link the app opens off the site: true when it's been
     * dealt with here, null to leave it to the next plugin, and in the end to Android. */
    public Boolean shouldOverrideLoad(Uri url) {
        return null;
    }
}
