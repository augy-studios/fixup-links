// uwuFix for Linux: the runner (docs/flutter-desktop-app-spec.md §2.7).
//
// - One copy at a time: a unique GtkApplication that handles its command line, so a second copy
//   (a uwu://fix link from the browser, a menu entry) hands its arguments to the first and exits;
//   the first opens what it was given (lib/desktop/desktop.dart), or just comes forward.
// - No title bar of the system's: the app draws its own (window_manager hides the decorations),
//   and the window shows once the Dart side has drawn and sized it.
// - The Fix a link widgets' windows (desktop_multi_window) get the plugins they use.
// - A window that can be clear, for Frosted Glass's blur behind it (glass.cc), which the Dart side
//   asks for over the app's channel as "setBackdrop".
#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <desktop_multi_window/desktop_multi_window_plugin.h>
#include <url_launcher_linux/url_launcher_plugin.h>
#include <window_manager/window_manager_plugin.h>

#include "flutter/generated_plugin_registrant.h"
#include "glass.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlView* view;
  FlMethodChannel* channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Gives each Fix a link widget's window (desktop_multi_window) the plugins it uses.
static void register_sub_window_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) window_manager_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "WindowManagerPlugin");
  window_manager_plugin_register_with_registrar(window_manager_registrar);
  g_autoptr(FlPluginRegistrar) url_launcher_registrar =
      fl_plugin_registry_get_registrar_for_plugin(registry, "UrlLauncherPlugin");
  url_launcher_plugin_register_with_registrar(url_launcher_registrar);
}

// The Dart side's asks of the window: Frosted Glass's backdrop on or off.
static void on_method_call(FlMethodChannel* channel, FlMethodCall* call, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (g_strcmp0(fl_method_call_get_name(call), "setBackdrop") == 0) {
    FlValue* arguments = fl_method_call_get_args(call);
    FlValue* on_value = nullptr;
    if (arguments != nullptr && fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP) {
      on_value = fl_value_lookup_string(arguments, "on");
    }
    const gboolean wants_backdrop =
        on_value != nullptr && fl_value_get_type(on_value) == FL_VALUE_TYPE_BOOL && fl_value_get_bool(on_value);
    g_autoptr(FlValue) result = fl_value_new_bool(glass_set_backdrop(self->window, self->view, wants_backdrop));
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  fl_method_call_respond(call, response, nullptr);
}

// Makes the app's one window: its Flutter view, the plugins, and the app's own channel. The window
// is realized but not shown; the Dart side shows it once it has drawn and sized it.
static void create_window(MyApplication* self) {
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  gtk_window_set_title(window, "uwuFix");
  gtk_window_set_default_size(window, 300, 360);
  glass_prepare(window);
  self->window = window;

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  self->view = view;
  GdkRGBA background_color;
  gdk_rgba_parse(&background_color, "#EEF2F0");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));
  // Shown by the Dart side (window_manager), not here, so it never flashes.
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  desktop_multi_window_plugin_set_window_created_callback(register_sub_window_plugins);

  // The app's own channel (lib/desktop/desktop.dart).
  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(fl_engine_get_binary_messenger(engine), "org.uwuapps.fixup/desktop",
                                        FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, on_method_call, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// A second copy's arguments, to the Dart side: a task, links, or just "come forward".
static void forward(MyApplication* self, gchar** arguments) {
  if (self->channel == nullptr) {
    return;
  }
  g_autoptr(FlValue) links = fl_value_new_list();
  const gchar* task = nullptr;
  for (gchar** argument = arguments; argument != nullptr && *argument != nullptr; argument++) {
    if (g_str_has_prefix(*argument, "--task=")) {
      // The task's name, after the 7 characters of "--task=".
      task = *argument + 7;
    } else if (g_str_has_prefix(*argument, "uwu:") || g_str_has_prefix(*argument, "http")) {
      fl_value_append_take(links, fl_value_new_string(*argument));
    }
  }
  if (task != nullptr) {
    g_autoptr(FlValue) task_value = fl_value_new_string(task);
    fl_method_channel_invoke_method(self->channel, "task", task_value, nullptr, nullptr, nullptr);
  } else if (fl_value_get_length(links) > 0) {
    fl_method_channel_invoke_method(self->channel, "open", links, nullptr, nullptr, nullptr);
  } else {
    fl_method_channel_invoke_method(self->channel, "activate", nullptr, nullptr, nullptr, nullptr);
  }
}

// Implements GApplication::command_line: in the first copy, for its own command line and for
// every later copy's.
static int my_application_command_line(GApplication* application, GApplicationCommandLine* command_line) {
  MyApplication* self = MY_APPLICATION(application);
  gint argument_count = 0;
  gchar** arguments = g_application_command_line_get_arguments(command_line, &argument_count);
  if (self->window == nullptr) {
    // Strip out the first argument as it is the binary name.
    self->dart_entrypoint_arguments = g_strdupv(arguments + 1);
    create_window(self);
  } else {
    forward(self, arguments + 1);
  }
  g_strfreev(arguments);
  return 0;
}

// Implements GApplication::activate: makes the window if there isn't one yet.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window == nullptr) {
    create_window(self);
  }
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->command_line = my_application_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->window = nullptr;
  self->view = nullptr;
  self->channel = nullptr;
}

MyApplication* my_application_new() {
  // The program's name as its application id, so desktops match the window to uwufix.desktop.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_COMMAND_LINE, nullptr));
}
