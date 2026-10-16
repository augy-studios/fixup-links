/*
 * The quick screen: a link shared to uwuFix (the share sheet, or uwuFix in its Direct Share row),
 * or text highlighted in any app with "Fix link" picked from the menu that pops up over it. The
 * site opens over the app you were in with the link already cleaned (main-site/script.js reads
 * ?text=), and Back returns you there.
 *
 * Highlighted in a box you can type in, the page also offers Replace, which puts the fixed link
 * back in place of the one highlighted (FixupPlugin.finish): Android's PROCESS_TEXT, answered with
 * the new text. Read-only text, such as a message someone sent you, can't be replaced, so the
 * page leaves Replace out.
 *
 * Its own task affinity, so an app that starts it as a new task doesn't bring the main app's
 * screen up behind it, and kept out of recents: it's a moment's errand, not a place to return to.
 */
package org.uwuapps.fixup;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;

import androidx.activity.OnBackPressedCallback;

import com.getcapacitor.BridgeActivity;

public class FixActivity extends BridgeActivity {
    static final String FROM_SHARE = "share";
    static final String FROM_SELECTION = "select";

    // What brought it here, for FixupPlugin.info's "quick": the share sheet or a selection, and
    // whether the selection can be replaced with the fixed link.
    String from = FROM_SHARE;
    boolean canReplace;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        registerPlugin(FixupPlugin.class);
        super.onCreate(savedInstanceState);

        // Back closes it, back to the app it came over, rather than walking the page's history.
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                finish();
            }
        });
    }

    // BridgeActivity calls this with the intent it was opened with, once the page has started
    // loading the site's home page; this loads the link into it instead.
    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);

        String text = null;
        if (Intent.ACTION_PROCESS_TEXT.equals(intent.getAction())) {
            from = FROM_SELECTION;
            CharSequence selected = intent.getCharSequenceExtra(Intent.EXTRA_PROCESS_TEXT);
            text = selected == null ? null : selected.toString();
            // Only an app waiting for an answer can take the new text back.
            canReplace = !intent.getBooleanExtra(Intent.EXTRA_PROCESS_TEXT_READONLY, false)
                    && getCallingActivity() != null;
        } else if (Intent.ACTION_SEND.equals(intent.getAction())) {
            from = FROM_SHARE;
            canReplace = false;
            text = intent.getStringExtra(Intent.EXTRA_TEXT);
            DirectShare.used(this);
        }

        if (bridge == null) return;
        String page = MainActivity.SITE + "/";
        if (text != null && !text.trim().isEmpty()) page += "?text=" + Uri.encode(text.trim());
        bridge.getWebView().loadUrl(page);
    }

    // The page's Replace, or Done: the fixed text back to the app that asked, when it can take
    // it, then back there.
    void finishWith(String text) {
        if (canReplace && text != null) {
            setResult(RESULT_OK, new Intent().putExtra(Intent.EXTRA_PROCESS_TEXT, text));
        }
        finish();
    }
}
