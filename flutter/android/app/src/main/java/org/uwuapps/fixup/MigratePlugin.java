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

    /**
     * Reads the site's old localStorage on the main thread with a hidden WebView: a blank page
     * loaded as if it were the site, then a script that copies out every key and value. Answers
     * { found, items }, with nothing found when this phone has no WebView at all.
     */
    @SuppressLint("SetJavaScriptEnabled")
    @PluginMethod
    public void read(PluginCall call) {
        getActivity().runOnUiThread(() -> {
            WebView webView;
            try {
                webView = new WebView(getActivity());
            } catch (RuntimeException exception) {
                // No WebView on this phone at all (it's being updated, say): nothing to read.
                JSObject result = new JSObject();
                result.put("found", false);
                result.put("items", new JSObject());
                call.resolve(result);
                return;
            }
            webView.getSettings().setJavaScriptEnabled(true);
            webView.getSettings().setDomStorageEnabled(true);
            webView.setWebViewClient(new WebViewClient() {
                private boolean done;

                @Override
                public void onPageFinished(WebView view, String url) {
                    if (done) {
                        return;
                    }
                    done = true;
                    view.evaluateJavascript(DUMP, (value) -> {
                        JSObject result = new JSObject();
                        JSObject items = new JSObject();
                        try {
                            // evaluateJavascript hands back the result as a JSON string literal.
                            String literal;
                            if (value == null) {
                                literal = "\"{}\"";
                            } else {
                                literal = value;
                            }
                            Object text = new JSONTokener(literal).nextValue();
                            String storedJson;
                            if (text instanceof String) {
                                storedJson = (String) text;
                            } else {
                                storedJson = "{}";
                            }
                            JSONObject allItems = new JSONObject(storedJson);
                            for (java.util.Iterator<String> keys = allItems.keys(); keys.hasNext(); ) {
                                String key = keys.next();
                                items.put(key, allItems.optString(key));
                            }
                        } catch (JSONException ignored) {
                            // Nothing readable: nothing to bring over.
                        }
                        result.put("found", items.length() > 0);
                        result.put("items", items);
                        call.resolve(result);
                        view.destroy();
                    });
                }
            });
            webView.loadDataWithBaseURL(MainActivity.SITE + "/", "<!doctype html><title></title>", "text/html", "utf-8", null);
        });
    }

    /** Once the data's safely in the app's own storage: the WebView's copy is left as it was,
     * so nothing's lost if the app is ever rolled back. */
    @PluginMethod
    public void done(PluginCall call) {
        call.resolve();
    }
}
