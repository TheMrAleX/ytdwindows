#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

// Single-instance plumbing:
// - GApplication flag G_APPLICATION_HANDLES_OPEN routes URI args from any
//   secondary launch to the primary instance via D-Bus, where they fire the
//   "open" signal. We forward those URIs to Dart on a method channel.
// - First launch (we are primary): URIs go through dart_entrypoint_arguments
//   so DeepLinkService.initial(launchArgs:) can handle them synchronously.
// - URIs that arrive before the first frame queue up; Dart drains them via the
//   "getPending" method call after registering its handler.
#define DEEP_LINK_CHANNEL "ytdlinux/deeplinks"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlView* view;
  FlMethodChannel* deep_link_channel;
  GQueue* pending_uris;  // queue of g_strdup'd uris awaiting Dart drain
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static gboolean is_uri_arg(const gchar* arg) {
  return g_str_has_prefix(arg, "ytdlinux:") ||
         g_str_has_prefix(arg, "http:") ||
         g_str_has_prefix(arg, "https:");
}

static void send_uri_to_dart(MyApplication* self, const gchar* uri) {
  if (self->deep_link_channel != nullptr) {
    g_autoptr(FlValue) args = fl_value_new_string(uri);
    fl_method_channel_invoke_method(self->deep_link_channel, "onLink", args,
                                    nullptr, nullptr, nullptr);
  } else {
    g_queue_push_tail(self->pending_uris, g_strdup(uri));
  }
}

static void deep_link_method_call_cb(FlMethodChannel* channel,
                                     FlMethodCall* method_call,
                                     gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (g_strcmp0(method, "getPending") == 0) {
    g_autoptr(FlValue) list = fl_value_new_list();
    while (!g_queue_is_empty(self->pending_uris)) {
      gchar* uri = static_cast<gchar*>(g_queue_pop_head(self->pending_uris));
      fl_value_append_take(list, fl_value_new_string(uri));
      g_free(uri);
    }
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(list));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  g_autoptr(GError) error = nullptr;
  fl_method_call_respond(method_call, response, &error);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // If the window already exists (e.g. a secondary --activate from D-Bus),
  // present it instead of building a new one.
  if (self->view != nullptr) {
    GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(self->view));
    if (GTK_IS_WINDOW(toplevel)) {
      gtk_window_present(GTK_WINDOW(toplevel));
    }
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "ytdlinux");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "ytdlinux");
  }

  gtk_window_set_default_size(window, 480, 500);
  // Min size: evita overflow (rail+thumb 180+texto+3 actions+padding) pero
  // mantiene flexibilidad para layouts compactos.
  gtk_widget_set_size_request(GTK_WIDGET(window), 480, 500);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Wire the deep-link channel as soon as the engine exists. The binary
  // messenger queues outgoing calls until Dart attaches a handler.
  self->view = view;
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->deep_link_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      DEEP_LINK_CHANNEL, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->deep_link_channel, deep_link_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::open. Fires on the primary instance whenever any
// process invokes the app with URI args (incl. via xdg-open / .desktop %u).
static void my_application_open(GApplication* application, GFile** files,
                                gint n_files, const gchar* hint) {
  MyApplication* self = MY_APPLICATION(application);

  // Make sure window exists.
  if (self->view == nullptr) {
    g_application_activate(application);
  } else {
    GtkWidget* toplevel = gtk_widget_get_toplevel(GTK_WIDGET(self->view));
    if (GTK_IS_WINDOW(toplevel)) {
      gtk_window_present(GTK_WINDOW(toplevel));
    }
  }

  for (gint i = 0; i < n_files; i++) {
    g_autofree gchar* uri = g_file_get_uri(files[i]);
    if (uri != nullptr) send_uri_to_dart(self, uri);
  }
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  gchar** argv = *arguments;

  // Split args into URIs (deep links) and ordinary entrypoint args.
  GPtrArray* uris = g_ptr_array_new_with_free_func(g_free);
  GPtrArray* dart_args = g_ptr_array_new_with_free_func(g_free);
  for (int i = 1; argv[i] != nullptr; i++) {
    if (is_uri_arg(argv[i])) {
      g_ptr_array_add(uris, g_strdup(argv[i]));
    } else {
      g_ptr_array_add(dart_args, g_strdup(argv[i]));
    }
  }

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    g_ptr_array_free(uris, TRUE);
    g_ptr_array_free(dart_args, TRUE);
    *exit_status = 1;
    return TRUE;
  }

  gboolean is_remote = g_application_get_is_remote(application);

  if (is_remote) {
    // Primary lives elsewhere — forward URIs over D-Bus and exit. The primary's
    // open handler will receive them.
    if (uris->len > 0) {
      GFile** files = g_new(GFile*, uris->len);
      for (guint i = 0; i < uris->len; i++) {
        files[i] = g_file_new_for_uri(static_cast<const gchar*>(uris->pdata[i]));
      }
      g_application_open(application, files, uris->len, "");
      for (guint i = 0; i < uris->len; i++) g_object_unref(files[i]);
      g_free(files);
    } else {
      g_application_activate(application);
    }
    g_ptr_array_free(uris, TRUE);
    g_ptr_array_free(dart_args, TRUE);
  } else {
    // We are primary. Stuff URIs into entrypoint args so the first launch
    // handles them inline (no D-Bus round-trip needed) and run normally.
    for (guint i = 0; i < uris->len; i++) {
      g_ptr_array_add(dart_args, g_strdup(static_cast<const gchar*>(uris->pdata[i])));
    }
    g_ptr_array_add(dart_args, nullptr);
    self->dart_entrypoint_arguments =
        reinterpret_cast<gchar**>(g_ptr_array_free(dart_args, FALSE));
    g_ptr_array_free(uris, TRUE);
    g_application_activate(application);
  }

  *exit_status = 0;
  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  if (self->pending_uris != nullptr) {
    g_queue_free_full(self->pending_uris, g_free);
    self->pending_uris = nullptr;
  }
  g_clear_object(&self->deep_link_channel);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->pending_uris = g_queue_new();
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_HANDLES_OPEN, nullptr));
}
