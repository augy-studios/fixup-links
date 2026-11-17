/*
 * What both of the app's screens share (MainActivity, the app, and FixActivity, the quick screen):
 * the Flutter screens (flutter/lib/) in a FlutterFragment, and this app's plugins reached from
 * the Dart side over the bridge (bridge/Bridge.java, flutter/lib/native/native_bridge.dart).
 *
 * An AppCompatActivity rather than a FlutterActivity, as the bridge's permission prompts and the
 * splash screen want one; the fragment's lifecycle calls are handed on as FlutterFragmentActivity
 * does them.
 */
package org.uwuapps.fixup;

import android.content.Intent;
import android.os.Bundle;
import android.widget.FrameLayout;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AppCompatActivity;
import androidx.fragment.app.FragmentManager;

import org.uwuapps.fixup.bridge.Bridge;

import io.flutter.embedding.android.FlutterEngineConfigurator;
import io.flutter.embedding.android.FlutterFragment;
import io.flutter.embedding.android.RenderMode;
import io.flutter.embedding.android.TransparencyMode;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.embedding.engine.plugins.util.GeneratedPluginRegister;
import io.flutter.plugin.common.BinaryMessenger;

public abstract class FlutterHost extends AppCompatActivity implements FlutterEngineConfigurator {
    private static final String FLUTTER_TAG = "flutter";

    protected Bridge pluginBridge;
    private FlutterFragment flutterFragment;
    // The engine's messenger when the engine came before the bridge: when Android brings the
    // app back after closing it in the background, super.onCreate restores the fragment, which
    // makes its engine before the bridge below exists.
    private BinaryMessenger earlyMessenger;

    Bridge bridge() {
        return pluginBridge;
    }

    /** The plugins this screen offers the Dart side. */
    protected abstract void registerPlugins(Bridge bridge);

    /** What an intent asks for: the one the screen was opened with, or a later one. */
    protected abstract void route(Intent intent);

    /**
     * Makes the bridge and this screen's plugins (connecting the engine's messenger if the engine
     * came first), then the Flutter fragment, reusing the one Android restored if there is one.
     * A fresh start is routed to what the screen was opened with.
     */
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        pluginBridge = new Bridge(this);
        registerPlugins(pluginBridge);
        if (earlyMessenger != null) {
            pluginBridge.connect(earlyMessenger);
            earlyMessenger = null;
        }

        FrameLayout root = new FrameLayout(this);
        root.setId(R.id.flutter_container);
        setContentView(root);
        FragmentManager fragmentManager = getSupportFragmentManager();
        flutterFragment = (FlutterFragment) fragmentManager.findFragmentByTag(FLUTTER_TAG);
        if (flutterFragment == null) {
            // Back is the Dart side's: its own screens first, then "Press back again to exit".
            flutterFragment = FlutterFragment.withNewEngine()
                    .renderMode(RenderMode.surface)
                    .transparencyMode(TransparencyMode.opaque)
                    .shouldAutomaticallyHandleOnBackPressed(true)
                    .build();
            fragmentManager.beginTransaction().add(R.id.flutter_container, flutterFragment, FLUTTER_TAG).commit();
        }
        if (savedInstanceState == null) {
            route(getIntent());
        }
    }

    // A FlutterFragment's engine leaves registering the Dart side's plugins (shared_preferences,
    // flutter_webrtc, ...) to its activity. Then the bridge to this app's own.
    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine engine) {
        GeneratedPluginRegister.registerGeneratedPlugins(engine);
        BinaryMessenger messenger = engine.getDartExecutor().getBinaryMessenger();
        if (pluginBridge != null) {
            pluginBridge.connect(messenger);
        } else {
            earlyMessenger = messenger;
        }
    }

    @Override
    public void cleanUpFlutterEngine(@NonNull FlutterEngine engine) {
        earlyMessenger = null;
        if (pluginBridge != null) {
            pluginBridge.disconnect();
        }
    }

    @Override
    protected void onNewIntent(@NonNull Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        if (flutterFragment != null) {
            flutterFragment.onNewIntent(intent);
        }
        route(intent);
    }

    @Override
    protected void onStart() {
        super.onStart();
        pluginBridge.onStart();
    }

    @Override
    public void onResume() {
        super.onResume();
        pluginBridge.onResume();
    }

    @Override
    public void onPause() {
        pluginBridge.onPause();
        super.onPause();
    }

    @Override
    protected void onStop() {
        pluginBridge.onStop();
        super.onStop();
    }

    @Override
    protected void onDestroy() {
        pluginBridge.onDestroy();
        super.onDestroy();
    }

    @Override
    public void onPostResume() {
        super.onPostResume();
        if (flutterFragment != null) {
            flutterFragment.onPostResume();
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (flutterFragment != null) {
            flutterFragment.onRequestPermissionsResult(requestCode, permissions, grantResults);
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (flutterFragment != null) {
            flutterFragment.onActivityResult(requestCode, resultCode, data);
        }
    }

    @Override
    protected void onUserLeaveHint() {
        super.onUserLeaveHint();
        if (flutterFragment != null) {
            flutterFragment.onUserLeaveHint();
        }
    }

    @Override
    public void onTrimMemory(int level) {
        super.onTrimMemory(level);
        if (flutterFragment != null) {
            flutterFragment.onTrimMemory(level);
        }
    }
}
