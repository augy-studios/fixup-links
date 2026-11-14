/*
 * The app's data from before it was a Flutter app (2.0.0 to 2.3.1 were the site in a WebView):
 * favourites, Places, uwuCoins, the eggs and everything else the site kept in the WebView's
 * localStorage for https://fixup.uwuapps.org. Read once, on the first launch after updating
 * (android/lib/data/migrate.dart), by a WebView that's never shown: a blank page given the
 * site's address as its own, so it sees the site's storage, with nothing fetched.
 *
 *   read()   { found, items: { key: value } }: every key the site kept, as strings
 */
package org.uwuapps.fixup;

import android.annotation.SuppressLint;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import org.json.JSONException;
import org.json.JSONObject;
import org.json.JSONTokener;
import org.uwuapps.fixup.bridge.AppPlugin;
import org.uwuapps.fixup.bridge.JSObject;
import org.uwuapps.fixup.bridge.Plugin;
import org.uwuapps.fixup.bridge.PluginCall;
import org.uwuapps.fixup.bridge.PluginMethod;

@AppPlugin(name = "Migrate")
public class MigratePlugin extends Plugin {

    private static final String DUMP = "(function(){var o={};try{for(var i=0;i<localStorage.length;i++){var k=localStorage.key(i);o[k]=localStorage.getItem(k);}}catch(e){}return JSON.stringify(o);})()";

    @SuppressLint("SetJavaScriptEnabled")
    @PluginMethod
    public void read(PluginCall call) {
        getActivity().runOnUiThread(() -> {
            WebView web;
            try {
                web = new WebView(getActivity());
            } catch (RuntimeException e) {
                // No WebView on this phone at all (it's being updated, say): nothing to read.
                JSObject out = new JSObject();
                out.put("found", false);
                out.put("items", new JSObject());
                call.resolve(out);
                return;
            }
            web.getSettings().setJavaScriptEnabled(true);
            web.getSettings().setDomStorageEnabled(true);
            web.setWebViewClient(new WebViewClient() {
                private boolean done;

                @Override
                public void onPageFinished(WebView view, String url) {
                    if (done) return;
                    done = true;
                    view.evaluateJavascript(DUMP, value -> {
                        JSObject out = new JSObject();
                        JSObject items = new JSObject();
                        try {
                            // evaluateJavascript hands back the result as a JSON string literal.
                            Object text = new JSONTokener(value == null ? "\"{}\"" : value).nextValue();
                            JSONObject all = new JSONObject(text instanceof String ? (String) text : "{}");
                            for (java.util.Iterator<String> keys = all.keys(); keys.hasNext(); ) {
                                String k = keys.next();
                                items.put(k, all.optString(k));
                            }
                        } catch (JSONException ignored) {
                            // Nothing readable: nothing to bring over.
                        }
                        out.put("found", items.length() > 0);
                        out.put("items", items);
                        call.resolve(out);
                        view.destroy();
                    });
                }
            });
            web.loadDataWithBaseURL(MainActivity.SITE + "/", "<!doctype html><title></title>", "text/html", "utf-8", null);
        });
    }

    /** Once the data's safely in the app's own storage: the WebView's copy is left as it was,
     * so nothing's lost if the app is ever rolled back. */
    @PluginMethod
    public void done(PluginCall call) {
        call.resolve();
    }
}
