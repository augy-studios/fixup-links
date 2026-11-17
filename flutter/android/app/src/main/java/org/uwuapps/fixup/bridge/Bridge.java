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
    private static final String PREFERENCES = "bridge.permissions";

    private final AppCompatActivity activity;
    private final Map<String, Plugin> plugins = new LinkedHashMap<>();
    private final Map<Plugin, Map<String, Method>> methods = new HashMap<>();
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final Handler workHandler;

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
        workHandler = new Handler(thread.getLooper());
        permissionLauncher = activity.registerForActivityResult(
                new ActivityResultContracts.RequestMultiplePermissions(),
                (results) -> {
                    afterPermissions();
                });
        activityLauncher = activity.registerForActivityResult(
                new ActivityResultContracts.StartActivityForResult(),
                (result) -> {
                    afterActivity(result);
                });
    }

    public Context getContext() {
        return activity;
    }

    public AppCompatActivity getActivity() {
        return activity;
    }

    /** For a plugin's load(): a result launcher of its own, as Android allows only then. */
    public <Input, Output> ActivityResultLauncher<Input> registerForActivityResult(
            ActivityResultContract<Input, Output> contract, ActivityResultCallback<Output> callback) {
        return activity.registerForActivityResult(contract, callback);
    }

    /**
     * Makes a plugin from its class, names it from its @AppPlugin annotation, and notes which of
     * its methods the Dart side may call (each public @PluginMethod that takes one PluginCall).
     */
    public void registerPlugin(Class<? extends Plugin> type) {
        AppPlugin pluginInfo = type.getAnnotation(AppPlugin.class);
        if (pluginInfo == null) {
            throw new IllegalArgumentException(type.getName() + " has no @AppPlugin");
        }
        Plugin plugin;
        try {
            plugin = type.getDeclaredConstructor().newInstance();
        } catch (ReflectiveOperationException exception) {
            throw new IllegalStateException("Couldn't make " + type.getName(), exception);
        }
        plugin.init(this, pluginInfo.name(), pluginInfo.permissions());
        Map<String, Method> callable = new HashMap<>();
        for (Method method : type.getMethods()) {
            boolean isPluginMethod = method.isAnnotationPresent(PluginMethod.class);
            boolean takesOneCall = method.getParameterCount() == 1
                    && method.getParameterTypes()[0] == PluginCall.class;
            if (isPluginMethod && takesOneCall) {
                callable.put(method.getName(), method);
            }
        }
        methods.put(plugin, callable);
        plugins.put(pluginInfo.name(), plugin);
        plugin.load();
    }

    public Plugin getPlugin(String name) {
        return plugins.get(name);
    }

    // ---------- the Dart side ----------

    /** The Flutter engine's messenger, once it's made (MainActivity.configureFlutterEngine). */
    public void connect(BinaryMessenger messenger) {
        MethodChannel newChannel = new MethodChannel(messenger, CHANNEL);
        newChannel.setMethodCallHandler((methodCall, result) -> {
            heard(methodCall, result);
        });
        synchronized (listening) {
            channel = newChannel;
            listening.clear();
        }
    }

    public void disconnect() {
        synchronized (listening) {
            if (channel != null) {
                channel.setMethodCallHandler(null);
            }
            channel = null;
            listening.clear();
        }
    }

    /** A message from the Dart side, on the main thread: hello, listen, unlisten or call. */
    private void heard(MethodCall methodCall, MethodChannel.Result result) {
        String plugin = methodCall.argument("plugin");
        String event = methodCall.argument("event");
        switch (methodCall.method) {
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
                    String optionsJson = methodCall.argument("options");
                    if (optionsJson == null || optionsJson.isEmpty()) {
                        options = new JSObject();
                    } else {
                        options = new JSObject(optionsJson);
                    }
                } catch (JSONException exception) {
                    options = new JSObject();
                }
                call(result, plugin, methodCall.argument("method"), options);
            }
            default -> result.notImplemented();
        }
    }

    /**
     * Runs a plugin's @PluginMethod on the bridge's own thread, with a PluginCall whose answer
     * goes back to the Dart side on the main thread. A method this app doesn't have is rejected
     * with "UNIMPLEMENTED".
     */
    private void call(MethodChannel.Result result, String pluginName, String methodName, JSObject options) {
        PluginCall.Answer answer = new PluginCall.Answer() {
            @Override
            public void resolve(JSObject data) {
                String json;
                if (data == null) {
                    json = null;
                } else {
                    json = data.toString();
                }
                mainHandler.post(() -> {
                    result.success(json);
                });
            }

            @Override
            public void reject(String message, String code, JSObject data) {
                String json;
                if (data == null) {
                    json = null;
                } else {
                    json = data.toString();
                }
                String errorCode;
                if (code == null) {
                    errorCode = "failed";
                } else {
                    errorCode = code;
                }
                String errorMessage;
                if (message == null) {
                    errorMessage = "Failed";
                } else {
                    errorMessage = message;
                }
                mainHandler.post(() -> {
                    result.error(errorCode, errorMessage, json);
                });
            }
        };
        PluginCall call = new PluginCall(pluginName, methodName, options, answer);
        Plugin plugin = plugins.get(pluginName);
        Method method;
        if (plugin == null) {
            method = null;
        } else {
            method = methods.get(plugin).get(methodName);
        }
        if (method == null) {
            call.reject(pluginName + "." + methodName + " isn't in this version of the app", "UNIMPLEMENTED");
            return;
        }
        workHandler.post(() -> {
            try {
                method.invoke(plugin, call);
            } catch (InvocationTargetException exception) {
                Log.e(TAG, pluginName + "." + methodName + " failed", exception.getCause());
                call.reject(failureMessage(exception));
            } catch (IllegalAccessException exception) {
                call.reject("Failed");
            }
        });
    }

    /** What a plugin method that threw says went wrong, or "Failed" when it says nothing. */
    private static String failureMessage(InvocationTargetException exception) {
        if (exception.getCause() == null) {
            return "Failed";
        }
        return String.valueOf(exception.getCause().getMessage());
    }

    private void send(String plugin, String event, JSObject data) {
        JSObject sentData;
        if (data == null) {
            sentData = new JSObject();
        } else {
            sentData = data;
        }
        Map<String, Object> arguments = new HashMap<>();
        arguments.put("plugin", plugin);
        arguments.put("event", event);
        arguments.put("data", sentData.toString());
        mainHandler.post(() -> {
            MethodChannel currentChannel;
            synchronized (listening) {
                currentChannel = channel;
            }
            if (currentChannel != null) {
                currentChannel.invokeMethod("event", arguments);
            }
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
        if (kept != null) {
            for (JSObject data : kept) {
                send(plugin, event, data);
            }
        }
    }

    boolean isListening(String plugin, String event) {
        synchronized (listening) {
            return channel != null && listening.contains(plugin + "." + event);
        }
    }

    void emit(Plugin plugin, String event, JSObject data, boolean retain) {
        String key = plugin.getName() + "." + event;
        synchronized (listening) {
            if (channel == null || !listening.contains(key)) {
                if (retain) {
                    JSObject keptData;
                    if (data == null) {
                        keptData = new JSObject();
                    } else {
                        keptData = data;
                    }
                    retained.computeIfAbsent(key, (missingKey) -> {
                        return new ArrayList<>();
                    }).add(keptData);
                }
                return;
            }
        }
        send(plugin.getName(), event, data);
    }

    // ---------- permissions ----------

    // Only asked for on the Android versions that have them; before, they're granted with the
    // app (or by another permission already asked, as Bluetooth's by location before 12).
    private static boolean applies(String permission) {
        int sdkVersion = Build.VERSION.SDK_INT;
        switch (permission) {
            case Manifest.permission.POST_NOTIFICATIONS, Manifest.permission.NEARBY_WIFI_DEVICES -> {
                return sdkVersion >= Build.VERSION_CODES.TIRAMISU;
            }
            case Manifest.permission.ACCESS_BACKGROUND_LOCATION, Manifest.permission.ACTIVITY_RECOGNITION -> {
                return sdkVersion >= Build.VERSION_CODES.Q;
            }
            case Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT,
                 Manifest.permission.BLUETOOTH_ADVERTISE -> {
                return sdkVersion >= Build.VERSION_CODES.S;
            }
            default -> {
                return true;
            }
        }
    }

    private boolean granted(String permission) {
        return !applies(permission)
                || ContextCompat.checkSelfPermission(activity, permission) == PackageManager.PERMISSION_GRANTED;
    }

    private SharedPreferences askedPreferences() {
        return activity.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE);
    }

    /** The state of a set of permissions together: granted only when every one is. */
    public PermissionState permissionState(String... strings) {
        boolean denied = false;
        boolean prompt = false;
        boolean rationale = false;
        for (String permission : strings) {
            if (granted(permission)) {
                continue;
            }
            if (activity.shouldShowRequestPermissionRationale(permission)) {
                rationale = true;
            } else if (askedPreferences().getBoolean(permission, false)) {
                denied = true;
            } else {
                prompt = true;
            }
        }
        if (denied) {
            return PermissionState.DENIED;
        }
        if (prompt) {
            return PermissionState.PROMPT;
        }
        if (rationale) {
            return PermissionState.PROMPT_WITH_RATIONALE;
        }
        return PermissionState.GRANTED;
    }

    void requestPermissions(Plugin plugin, String[] strings, PluginCall call, String callback) {
        List<String> wanted = new ArrayList<>();
        for (String permission : strings) {
            if (!granted(permission) && !wanted.contains(permission)) {
                wanted.add(permission);
            }
        }
        mainHandler.post(() -> {
            if (wanted.isEmpty()) {
                invoke(plugin, callback, call, null);
            } else {
                ask(new PermissionAsk(wanted.toArray(new String[0]), plugin, call, callback, null));
            }
        });
    }

    /** For the Dart side's own asks (location for Near me, the camera for a scan): Android's
     * prompt for these, then whether they're all allowed. On the main thread. */
    public void askFor(String[] strings, java.util.function.Consumer<Boolean> then) {
        List<String> wanted = new ArrayList<>();
        for (String permission : strings) {
            if (!granted(permission)) {
                wanted.add(permission);
            }
        }
        if (wanted.isEmpty()) {
            then.accept(true);
        } else {
            ask(new PermissionAsk(wanted.toArray(new String[0]), null, null, null, then));
        }
    }

    // One prompt at a time, as Android shows them.
    private void ask(PermissionAsk permissionAsk) {
        permissionAsks.add(permissionAsk);
        if (permissionAsks.size() == 1) {
            permissionLauncher.launch(permissionAsk.strings());
        }
    }

    /**
     * Android's prompt answered: notes each permission as asked (so a refusal can later be told
     * apart from never asking), hands the answer on, then shows the next prompt waiting, if any.
     */
    private void afterPermissions() {
        PermissionAsk finishedAsk = permissionAsks.poll();
        if (finishedAsk != null) {
            SharedPreferences.Editor editor = askedPreferences().edit();
            for (String permission : finishedAsk.strings()) {
                editor.putBoolean(permission, true);
            }
            editor.apply();
            if (finishedAsk.then() != null) {
                boolean allGranted = true;
                for (String permission : finishedAsk.strings()) {
                    allGranted &= granted(permission);
                }
                finishedAsk.then().accept(allGranted);
            } else {
                invoke(finishedAsk.plugin(), finishedAsk.callback(), finishedAsk.call(), null);
            }
        }
        PermissionAsk nextAsk = permissionAsks.peek();
        if (nextAsk != null) {
            permissionLauncher.launch(nextAsk.strings());
        }
    }

    // ---------- other activities ----------

    void startActivityForResult(Plugin plugin, PluginCall call, Intent intent, String callback) {
        // Thrown here, as Capacitor did, when nothing on the phone can take it.
        if (intent.resolveActivity(activity.getPackageManager()) == null) {
            throw new android.content.ActivityNotFoundException(intent.toString());
        }
        mainHandler.post(() -> {
            activityAsks.add(new ActivityAsk(plugin, intent, call, callback));
            if (activityAsks.size() == 1) {
                launch(intent);
            }
        });
    }

    private void launch(Intent intent) {
        try {
            activityLauncher.launch(intent);
        } catch (android.content.ActivityNotFoundException exception) {
            afterActivity(new ActivityResult(AppCompatActivity.RESULT_CANCELED, null));
        }
    }

    private void afterActivity(ActivityResult result) {
        ActivityAsk finishedAsk = activityAsks.poll();
        if (finishedAsk != null) {
            invoke(finishedAsk.plugin(), finishedAsk.callback(), finishedAsk.call(), result);
        }
        ActivityAsk nextAsk = activityAsks.peek();
        if (nextAsk != null) {
            launch(nextAsk.intent());
        }
    }

    // A plugin's @PermissionCallback (call) or @ActivityCallback (call, result), by name, private
    // or not.
    private void invoke(Plugin plugin, String name, PluginCall call, ActivityResult result) {
        if (name == null) {
            return;
        }
        for (Class<?> type = plugin.getClass(); type != null && type != Object.class; type = type.getSuperclass()) {
            for (Method method : type.getDeclaredMethods()) {
                if (!method.getName().equals(name)) {
                    continue;
                }
                boolean withResult = method.getParameterCount() == 2
                        && method.isAnnotationPresent(ActivityCallback.class);
                boolean plain = method.getParameterCount() == 1
                        && method.isAnnotationPresent(PermissionCallback.class);
                if (!withResult && !plain) {
                    continue;
                }
                try {
                    method.setAccessible(true);
                    if (withResult) {
                        method.invoke(plugin, call, result);
                    } else {
                        method.invoke(plugin, call);
                    }
                } catch (InvocationTargetException exception) {
                    Log.e(TAG, plugin.getName() + "." + name + " failed", exception.getCause());
                    call.reject(failureMessage(exception));
                } catch (IllegalAccessException exception) {
                    call.reject("Failed");
                }
                return;
            }
        }
        call.reject("No callback " + name);
    }

    // ---------- the activity's lifecycle ----------

    public void onStart() {
        for (Plugin plugin : plugins.values()) {
            plugin.handleOnStart();
        }
    }

    public void onResume() {
        for (Plugin plugin : plugins.values()) {
            plugin.handleOnResume();
        }
    }

    public void onPause() {
        for (Plugin plugin : plugins.values()) {
            plugin.handleOnPause();
        }
    }

    public void onStop() {
        for (Plugin plugin : plugins.values()) {
            plugin.handleOnStop();
        }
    }

    public void onDestroy() {
        for (Plugin plugin : plugins.values()) {
            plugin.handleOnDestroy();
        }
        disconnect();
        workHandler.getLooper().quitSafely();
    }

    public void onNewIntent(Intent intent) {
        for (Plugin plugin : plugins.values()) {
            plugin.handleOnNewIntent(intent);
        }
    }

    /** A link off the site (an intent: link, say): true when a plugin dealt with it. */
    public boolean shouldOverrideLoad(Uri url) {
        for (Plugin plugin : plugins.values()) {
            Boolean handled = plugin.shouldOverrideLoad(url);
            if (handled != null) {
                return handled;
            }
        }
        return false;
    }
}
