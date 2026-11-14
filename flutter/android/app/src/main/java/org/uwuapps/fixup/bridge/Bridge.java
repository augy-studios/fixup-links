package org.uwuapps.fixup.bridge;

import android.Manifest;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Handler;
import android.os.HandlerThread;
import android.os.Looper;
import android.util.Log;

import androidx.activity.result.ActivityResult;
import androidx.activity.result.ActivityResultCallback;
import androidx.activity.result.ActivityResultLauncher;
import androidx.activity.result.contract.ActivityResultContract;
import androidx.activity.result.contract.ActivityResultContracts;
import androidx.appcompat.app.AppCompatActivity;
import androidx.core.content.ContextCompat;

import org.json.JSONException;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

import java.lang.reflect.InvocationTargetException;
import java.lang.reflect.Method;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * The Dart side's way to the app's plugins (android/lib/native/native_bridge.dart): what
 * Capacitor did for the page from 2.0.0 to 2.3.1, kept to what the plugins use, over one
 * Flutter method channel, CHANNEL.
 *
 *   Dart -> app   call    { plugin, method, options }   answered with the result as JSON, or
 *                                                       an error (code, message, data as JSON)
 *                 listen / unlisten  { plugin, event }
 *                 hello   the Dart side has started (again): no listeners yet
 *   app -> Dart   event   { plugin, event, data }      data as JSON
 */
public final class Bridge {
    private static final String TAG = "Fixup";
    public static final String CHANNEL = "org.uwuapps.fixup/bridge";
    private static final String PREFS = "bridge.permissions";

    private final AppCompatActivity activity;
    private final Map<String, Plugin> plugins = new LinkedHashMap<>();
    private final Map<Plugin, Map<String, Method>> methods = new HashMap<>();
    private final Handler main = new Handler(Looper.getMainLooper());
    private final Handler work;

    // The Dart side, and what it listens for ("Trip.location"). Events nobody hears yet, kept
    // for the first listener when they're asked to be (notifyListeners' retain).
    private MethodChannel channel;
    private final java.util.Set<String> listening = new java.util.HashSet<>();
    private final Map<String, List<JSObject>> retained = new HashMap<>();

    private final ActivityResultLauncher<String[]> permissionLauncher;
    private final ActivityResultLauncher<Intent> activityLauncher;
    private final ArrayDeque<PermissionAsk> permissionAsks = new ArrayDeque<>();
    private final ArrayDeque<ActivityAsk> activityAsks = new ArrayDeque<>();

    // A plugin's (on to its callback), or the Dart side's own (on to then, with whether they're
    // all allowed).
    private record PermissionAsk(String[] strings, Plugin plugin, PluginCall call, String callback,
                                 java.util.function.Consumer<Boolean> then) {}

    private record ActivityAsk(Plugin plugin, Intent intent, PluginCall call, String callback) {}

    /** Made in the activity's onCreate, before it starts: Android needs the result launchers
     * registered by then. */
    public Bridge(AppCompatActivity activity) {
        this.activity = activity;
        HandlerThread thread = new HandlerThread("FixupPlugins");
        thread.start();
        work = new Handler(thread.getLooper());
        permissionLauncher = activity.registerForActivityResult(new ActivityResultContracts.RequestMultiplePermissions(), r -> afterPermissions());
        activityLauncher = activity.registerForActivityResult(new ActivityResultContracts.StartActivityForResult(), this::afterActivity);
    }

    public Context getContext() {
        return activity;
    }

    public AppCompatActivity getActivity() {
        return activity;
    }

    /** For a plugin's load(): a result launcher of its own, as Android allows only then. */
    public <I, O> ActivityResultLauncher<I> registerForActivityResult(ActivityResultContract<I, O> contract, ActivityResultCallback<O> callback) {
        return activity.registerForActivityResult(contract, callback);
    }

    public void registerPlugin(Class<? extends Plugin> type) {
        AppPlugin about = type.getAnnotation(AppPlugin.class);
        if (about == null) throw new IllegalArgumentException(type.getName() + " has no @AppPlugin");
        Plugin plugin;
        try {
            plugin = type.getDeclaredConstructor().newInstance();
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException("Couldn't make " + type.getName(), e);
        }
        plugin.init(this, about.name(), about.permissions());
        Map<String, Method> callable = new HashMap<>();
        for (Method m : type.getMethods()) {
            if (m.isAnnotationPresent(PluginMethod.class) && m.getParameterCount() == 1 && m.getParameterTypes()[0] == PluginCall.class) {
                callable.put(m.getName(), m);
            }
        }
        methods.put(plugin, callable);
        plugins.put(about.name(), plugin);
        plugin.load();
    }

    public Plugin getPlugin(String name) {
        return plugins.get(name);
    }

    // ---------- the Dart side ----------

    /** The Flutter engine's messenger, once it's made (MainActivity.configureFlutterEngine). */
    public void connect(BinaryMessenger messenger) {
        MethodChannel c = new MethodChannel(messenger, CHANNEL);
        c.setMethodCallHandler(this::heard);
        synchronized (listening) {
            channel = c;
            listening.clear();
        }
    }

    public void disconnect() {
        synchronized (listening) {
            if (channel != null) channel.setMethodCallHandler(null);
            channel = null;
            listening.clear();
        }
    }

    // On the main thread, from Dart.
    private void heard(MethodCall m, MethodChannel.Result result) {
        String plugin = m.argument("plugin");
        String event = m.argument("event");
        switch (m.method) {
            case "hello" -> {
                synchronized (listening) {
                    listening.clear();
                }
                result.success(null);
            }
            case "listen" -> {
                listen(plugin, event);
                result.success(null);
            }
            case "unlisten" -> {
                synchronized (listening) {
                    listening.remove(plugin + "." + event);
                }
                result.success(null);
            }
            case "call" -> {
                JSObject options;
                try {
                    String o = m.argument("options");
                    options = o == null || o.isEmpty() ? new JSObject() : new JSObject(o);
                } catch (JSONException e) {
                    options = new JSObject();
                }
                call(result, plugin, m.argument("method"), options);
            }
            default -> result.notImplemented();
        }
    }

    private void call(MethodChannel.Result result, String pluginName, String methodName, JSObject options) {
        PluginCall.Answer answer = new PluginCall.Answer() {
            @Override
            public void resolve(JSObject data) {
                String json = data == null ? null : data.toString();
                main.post(() -> result.success(json));
            }

            @Override
            public void reject(String message, String code, JSObject data) {
                String json = data == null ? null : data.toString();
                main.post(() -> result.error(code == null ? "failed" : code, message == null ? "Failed" : message, json));
            }
        };
        PluginCall call = new PluginCall(pluginName, methodName, options, answer);
        Plugin plugin = plugins.get(pluginName);
        Method method = plugin == null ? null : methods.get(plugin).get(methodName);
        if (method == null) {
            call.reject(pluginName + "." + methodName + " isn't in this version of the app", "UNIMPLEMENTED");
            return;
        }
        work.post(() -> {
            try {
                method.invoke(plugin, call);
            } catch (InvocationTargetException e) {
                Log.e(TAG, pluginName + "." + methodName + " failed", e.getCause());
                call.reject(e.getCause() == null ? "Failed" : String.valueOf(e.getCause().getMessage()));
            } catch (IllegalAccessException e) {
                call.reject("Failed");
            }
        });
    }

    private void send(String plugin, String event, JSObject data) {
        Map<String, Object> args = new HashMap<>();
        args.put("plugin", plugin);
        args.put("event", event);
        args.put("data", (data == null ? new JSObject() : data).toString());
        main.post(() -> {
            MethodChannel c;
            synchronized (listening) {
                c = channel;
            }
            if (c != null) c.invokeMethod("event", args);
        });
    }

    // ---------- events ----------

    private void listen(String plugin, String event) {
        String key = plugin + "." + event;
        List<JSObject> kept;
        synchronized (listening) {
            listening.add(key);
            kept = retained.remove(key);
        }
        if (kept != null) for (JSObject data : kept) send(plugin, event, data);
    }

    boolean listening(String plugin, String event) {
        synchronized (listening) {
            return channel != null && listening.contains(plugin + "." + event);
        }
    }

    void emit(Plugin plugin, String event, JSObject data, boolean retain) {
        String key = plugin.getName() + "." + event;
        synchronized (listening) {
            if (channel == null || !listening.contains(key)) {
                if (retain) retained.computeIfAbsent(key, k -> new ArrayList<>()).add(data == null ? new JSObject() : data);
                return;
            }
        }
        send(plugin.getName(), event, data);
    }

    // ---------- permissions ----------

    // Only asked for on the Android versions that have them; before, they're granted with the
    // app (or by another permission already asked, as Bluetooth's by location before 12).
    private static boolean applies(String permission) {
        int sdk = Build.VERSION.SDK_INT;
        return switch (permission) {
            case Manifest.permission.POST_NOTIFICATIONS, Manifest.permission.NEARBY_WIFI_DEVICES -> sdk >= Build.VERSION_CODES.TIRAMISU;
            case Manifest.permission.ACCESS_BACKGROUND_LOCATION, Manifest.permission.ACTIVITY_RECOGNITION -> sdk >= Build.VERSION_CODES.Q;
            case Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT, Manifest.permission.BLUETOOTH_ADVERTISE -> sdk >= Build.VERSION_CODES.S;
            default -> true;
        };
    }

    private boolean granted(String permission) {
        return !applies(permission) || ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED;
    }

    private SharedPreferences asked() {
        return activity.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    /** The state of a set of permissions together: granted only when every one is. */
    public PermissionState permissionState(String... strings) {
        boolean denied = false, prompt = false, rationale = false;
        for (String p : strings) {
            if (granted(p)) continue;
            if (activity.shouldShowRequestPermissionRationale(p)) rationale = true;
            else if (asked().getBoolean(p, false)) denied = true;
            else prompt = true;
        }
        return denied ? PermissionState.DENIED : prompt ? PermissionState.PROMPT
                : rationale ? PermissionState.PROMPT_WITH_RATIONALE : PermissionState.GRANTED;
    }

    void requestPermissions(Plugin plugin, String[] strings, PluginCall call, String callback) {
        List<String> wanted = new ArrayList<>();
        for (String p : strings) if (!granted(p) && !wanted.contains(p)) wanted.add(p);
        main.post(() -> {
            if (wanted.isEmpty()) invoke(plugin, callback, call, null);
            else ask(new PermissionAsk(wanted.toArray(new String[0]), plugin, call, callback, null));
        });
    }

    /** For the Dart side's own asks (location for Near me, the camera for a scan): Android's
     * prompt for these, then whether they're all allowed. On the main thread. */
    public void askFor(String[] strings, java.util.function.Consumer<Boolean> then) {
        List<String> wanted = new ArrayList<>();
        for (String p : strings) if (!granted(p)) wanted.add(p);
        if (wanted.isEmpty()) then.accept(true);
        else ask(new PermissionAsk(wanted.toArray(new String[0]), null, null, null, then));
    }

    // One prompt at a time, as Android shows them.
    private void ask(PermissionAsk a) {
        permissionAsks.add(a);
        if (permissionAsks.size() == 1) permissionLauncher.launch(a.strings());
    }

    private void afterPermissions() {
        PermissionAsk done = permissionAsks.poll();
        if (done != null) {
            SharedPreferences.Editor edit = asked().edit();
            for (String p : done.strings()) edit.putBoolean(p, true);
            edit.apply();
            if (done.then() != null) {
                boolean all = true;
                for (String p : done.strings()) all &= granted(p);
                done.then().accept(all);
            } else {
                invoke(done.plugin(), done.callback(), done.call(), null);
            }
        }
        PermissionAsk next = permissionAsks.peek();
        if (next != null) permissionLauncher.launch(next.strings());
    }

    // ---------- other activities ----------

    void startActivityForResult(Plugin plugin, PluginCall call, Intent intent, String callback) {
        // Thrown here, as Capacitor did, when nothing on the phone can take it.
        if (intent.resolveActivity(activity.getPackageManager()) == null) {
            throw new android.content.ActivityNotFoundException(intent.toString());
        }
        main.post(() -> {
            activityAsks.add(new ActivityAsk(plugin, intent, call, callback));
            if (activityAsks.size() == 1) launch(intent);
        });
    }

    private void launch(Intent intent) {
        try {
            activityLauncher.launch(intent);
        } catch (android.content.ActivityNotFoundException e) {
            afterActivity(new ActivityResult(AppCompatActivity.RESULT_CANCELED, null));
        }
    }

    private void afterActivity(ActivityResult result) {
        ActivityAsk done = activityAsks.poll();
        if (done != null) invoke(done.plugin(), done.callback(), done.call(), result);
        ActivityAsk next = activityAsks.peek();
        if (next != null) launch(next.intent());
    }

    // A plugin's @PermissionCallback (call) or @ActivityCallback (call, result), by name, private
    // or not.
    private void invoke(Plugin plugin, String name, PluginCall call, ActivityResult result) {
        if (name == null) return;
        for (Class<?> c = plugin.getClass(); c != null && c != Object.class; c = c.getSuperclass()) {
            for (Method m : c.getDeclaredMethods()) {
                if (!m.getName().equals(name)) continue;
                boolean withResult = m.getParameterCount() == 2 && m.isAnnotationPresent(ActivityCallback.class);
                boolean plain = m.getParameterCount() == 1 && m.isAnnotationPresent(PermissionCallback.class);
                if (!withResult && !plain) continue;
                try {
                    m.setAccessible(true);
                    if (withResult) m.invoke(plugin, call, result);
                    else m.invoke(plugin, call);
                } catch (InvocationTargetException e) {
                    Log.e(TAG, plugin.getName() + "." + name + " failed", e.getCause());
                    call.reject(e.getCause() == null ? "Failed" : String.valueOf(e.getCause().getMessage()));
                } catch (IllegalAccessException e) {
                    call.reject("Failed");
                }
                return;
            }
        }
        call.reject("No callback " + name);
    }

    // ---------- the activity's lifecycle ----------

    public void onStart() {
        for (Plugin p : plugins.values()) p.handleOnStart();
    }

    public void onResume() {
        for (Plugin p : plugins.values()) p.handleOnResume();
    }

    public void onPause() {
        for (Plugin p : plugins.values()) p.handleOnPause();
    }

    public void onStop() {
        for (Plugin p : plugins.values()) p.handleOnStop();
    }

    public void onDestroy() {
        for (Plugin p : plugins.values()) p.handleOnDestroy();
        disconnect();
        work.getLooper().quitSafely();
    }

    public void onNewIntent(Intent intent) {
        for (Plugin p : plugins.values()) p.handleOnNewIntent(intent);
    }

    /** A link off the site (an intent: link, say): true when a plugin dealt with it. */
    public boolean shouldOverrideLoad(Uri url) {
        for (Plugin p : plugins.values()) {
            Boolean handled = p.shouldOverrideLoad(url);
            if (handled != null) return handled;
        }
        return false;
    }
}
