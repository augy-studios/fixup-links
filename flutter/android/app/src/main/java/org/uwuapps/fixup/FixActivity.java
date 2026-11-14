/*
 * The quick screen: a link shared to uwuFix (the share sheet, or uwuFix in its Direct Share row),
 * text highlighted in any app with "Fix link" picked from the menu that pops up over it, or the
 * link you've copied, from a widget's paste button (Widgets.java). The app's own screen opens
 * over the app you were in with the link already cleaned (flutter/lib/app/quick.dart), and Back
 * returns you there.
 *
 * Highlighted in a box you can type in, the screen also offers Replace, which puts the fixed link
 * back in place of the one highlighted (FixupPlugin.finish): Android's PROCESS_TEXT, answered with
 * the new text. Read-only text, such as a message someone sent you, can't be replaced, so Replace
 * is left out.
 *
 * Its own task affinity, so an app that starts it as a new task doesn't bring the main app's
 * screen up behind it, and kept out of recents: it's a moment's errand, not a place to return to.
 */
package org.uwuapps.fixup;

import android.content.Intent;
import android.widget.Toast;

import org.uwuapps.fixup.bridge.Bridge;

public class FixActivity extends FlutterHost {
    static final String FROM_SHARE = "share";
    static final String FROM_SELECTION = "select";
    static final String FROM_COPIED = "copied";

    // A widget's paste button: fix whatever's copied.
    static final String ACTION_FIX_COPIED = "org.uwuapps.fixup.FIX_COPIED";

    // What brought it here, for FixupPlugin.info's "quick": the share sheet, a selection, or the
    // clipboard; whether the selection can be replaced with the fixed link; and the text.
    String from = FROM_SHARE;
    boolean canReplace;
    String text = "";

    // Opened to fix what's copied, which can't be read until the window has focus.
    private boolean waitingForClipboard;

    @Override
    protected void registerPlugins(Bridge bridge) {
        bridge.registerPlugin(FixupPlugin.class);
    }

    @Override
    protected void route(Intent intent) {
        if (Intent.ACTION_PROCESS_TEXT.equals(intent.getAction())) {
            from = FROM_SELECTION;
            CharSequence selected = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT);
            text = selected == null ? "" : selected.toString();
            // Only an app waiting for an answer can take the new text back.
            canReplace = !intent.getBooleanExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, false)
                    && getCallingActivity() != null;
        } else if (Intent.ACTION_SEND.equals(intent.getAction())) {
            from = FROM_SHARE;
            canReplace = false;
            String shared = intent.getStringExtra(Intent.EXTRA_TEXT);
            text = shared == null ? "" : shared;
            DirectShare.used(this);
        } else if (ACTION_FIX_COPIED.equals(intent.getAction())) {
            from = FROM_COPIED;
            canReplace = false;
            text = "";
            // Android 10 and later only let the app in front read the clipboard, and it isn't in
            // front until its window has focus.
            waitingForClipboard = true;
            if (hasWindowFocus()) fixCopied();
            return;
        }
        FixupPlugin.quick(this);
    }

    @Override
    public void onWindowFocusChanged(boolean hasFocus) {
        super.onWindowFocusChanged(hasFocus);
        if (hasFocus && waitingForClipboard) fixCopied();
    }

    private void fixCopied() {
        waitingForClipboard = false;
        text = FixupPlugin.clipboardText(this);
        if (text.trim().isEmpty()) {
            // The screen's already up, with its box to type or paste a link into.
            Toast.makeText(this, R.string.nothing_copied, Toast.LENGTH_LONG).show();
        }
        FixupPlugin.quick(this);
    }

    // Replace, or Done: the fixed text back to the app that asked, when it can take it, then
    // back there.
    void finishWith(String fixed) {
        if (canReplace && fixed != null) {
            setResult(RESULT_OK, new Intent().putExtra(Intent.EXTRA_PROCESS_TEXT, fixed));
        }
        finish();
    }
}
