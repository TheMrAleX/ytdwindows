#include "flutter_window.h"

#include <flutter/standard_method_codec.h>

#include <optional>

#include "deep_link.h"
#include "flutter/generated_plugin_registrant.h"
#include "utils.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  // Canal de deep links. Espejo del lado Linux (my_application.cc):
  // "getPending" drena las URIs encoladas antes de que Dart enganchara su
  // handler; "onLink" entrega las que llegan en vivo.
  deep_link_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "ytdlinux/deeplinks",
          &flutter::StandardMethodCodec::GetInstance());
  deep_link_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "getPending") {
          flutter::EncodableList list;
          for (const auto& uri : pending_uris_) {
            list.push_back(flutter::EncodableValue(uri));
          }
          pending_uris_.clear();
          result->Success(flutter::EncodableValue(list));
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }
  deep_link_channel_ = nullptr;

  Win32Window::OnDestroy();
}

void FlutterWindow::HandleDeepLink(const std::string& uri) {
  if (uri.empty()) {
    return;
  }
  if (deep_link_channel_) {
    deep_link_channel_->InvokeMethod(
        "onLink", std::make_unique<flutter::EncodableValue>(uri));
  } else {
    // Dart aún no listo; encolar para drenar con getPending.
    pending_uris_.push_back(uri);
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
    case WM_COPYDATA: {
      auto* cds = reinterpret_cast<COPYDATASTRUCT*>(lparam);
      if (cds != nullptr && cds->dwData == kDeepLinkCopyDataMagic &&
          cds->lpData != nullptr) {
        const wchar_t* uri16 = reinterpret_cast<const wchar_t*>(cds->lpData);
        HandleDeepLink(Utf8FromUtf16(uri16));
        return TRUE;
      }
      break;
    }
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
