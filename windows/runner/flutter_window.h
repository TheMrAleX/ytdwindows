#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>
#include <vector>

#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

  // Entrega una URI de deep link (llegada vía WM_COPYDATA desde una segunda
  // instancia) a Dart por el method channel. Si Dart aún no enganchó su
  // handler, la encola para drenarla con "getPending".
  void HandleDeepLink(const std::string& uri);

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Canal hacia Dart para entregar deep links (ytdlinux://...).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      deep_link_channel_;

  // URIs que llegaron antes de que Dart registrara su handler.
  std::vector<std::string> pending_uris_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
