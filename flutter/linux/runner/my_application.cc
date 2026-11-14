// uwuFix for Linux: the runner (docs/flutter-desktop-app-spec.md §2.7).
//
// - One copy at a time: a unique GtkApplication that handles its command line, so a second copy
//   (a uwu://fix link from the browser, a menu entry) hands its arguments to the first and exits;
//   the first opens what it was given (lib/desktop/desktop.dart), or just comes forward.
// - No title bar of the system's: the app draws its own (window_manager hides the decorations),
//   and the window shows once the Dart side has drawn and sized it.
// - The Fix a link widgets' windows (desktop_multi_window) get the plugins they use.
#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <desktop_multi_window/desktop_multi_window_plugin.h>
#include <url_launcher_linux/url_launcher_plugin.h>
#include <window_manager/window_manager_plugin.h>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* window;
  FlMethodChannel* channel;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static void register_sub_window_plugins(FlPluginRegistry* registry) {
  g_autoptr(FlPluginRegistrar) wm = fl_plugin_registry_get_registrar_for_plugin(registry, "WindowManagerPlugin");
  window_manager_plugin_register_with_registrar(wm);
  g_autoptr(FlPluginRegistrar) url = fl_plugin_registry_get_registrar_for_plugin(registry, "UrlLauncherPlugin");
  url_launcher_plugin_register_with_registrar(url);
}

static void create_window(MyApplication* self) {
  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(self)));
  gtk_window_set_title(window, "uwuFix");
  gtk_window_set_default_size(window, 300, 360);
  self->window = window;

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
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

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// A second copy's arguments, to the Dart side: a task, links, or just "come forward".
static void forward(MyApplication* self, gchar** args) {
  if (self->channel == nullptr) return;
  g_autoptr(FlValue) links = fl_value_new_list();
  const gchar* task = nullptr;
  for (gchar** a = args; a != nullptr && *a != nullptr; a++) {
    if (g_str_has_prefix(*a, "--task=")) {
      task = *a + 7;
    } else if (g_str_has_prefix(*a, "uwu:") || g_str_has_prefix(*a, "http")) {
      fl_value_append_take(links, fl_value_new_string(*a));
    }
  }
  if (task != nullptr) {
    g_autoptr(FlValue) v = fl_value_new_string(task);
    fl_method_channel_invoke_method(self->channel, "task", v, nullptr, nullptr, nullptr);
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
  gint argc = 0;
  gchar** argv = g_application_command_line_get_arguments(command_line, &argc);
  if (self->window == nullptr) {
    // Strip out the first argument as it is the binary name.
    self->dart_entrypoint_arguments = g_strdupv(argv + 1);
    create_window(self);
  } else {
    forward(self, argv + 1);
  }
  g_strfreev(argv);
  return 0;
}

static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  if (self->window == nullptr) create_window(self);
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
  self->channel = nullptr;
}

MyApplication* my_application_new() {
  // The program's name as its application id, so desktops match the window to uwufix.desktop.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_COMMAND_LINE, nullptr));
}
