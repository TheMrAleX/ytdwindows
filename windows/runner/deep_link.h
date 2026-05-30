#ifndef RUNNER_DEEP_LINK_H_
#define RUNNER_DEEP_LINK_H_

#include <windows.h>

#include <string>

// Plumbing para el esquema personalizado `ytdlinux://` en Windows.
//
// Flujo:
//  - Primer arranque: la URI llega como argumento de línea de comandos y se
//    pasa a Dart vía dart_entrypoint_arguments (DeepLinkService.initial).
//  - Con la app ya abierta: el navegador lanza una segunda instancia. Esa
//    instancia detecta (vía mutex con nombre) que ya hay una primaria, le
//    reenvía la URI por WM_COPYDATA y sale. La primaria la empuja a Dart por
//    el method channel `ytdlinux/deeplinks` (onLink).

// Identificador en CopyDataStruct::dwData para distinguir nuestros mensajes
// de cualquier otro WM_COPYDATA. ('Y','T','D','L')
constexpr ULONG_PTR kDeepLinkCopyDataMagic = 0x5954444C;

// Nombre del mutex global de instancia única.
constexpr wchar_t kSingleInstanceMutexName[] =
    L"Global\\ytdlinux_single_instance";

// Esquema registrado en el registro de Windows.
constexpr wchar_t kDeepLinkScheme[] = L"ytdlinux";

// Título de la ventana principal (debe coincidir con el usado en main.cpp al
// crear la ventana) — se usa para localizar la instancia primaria.
constexpr wchar_t kMainWindowTitle[] = L"ytdlinux";

// Registra el esquema `ytdlinux://` en HKCU\Software\Classes (no requiere
// admin). Idempotente: se llama en cada arranque para mantener la ruta del
// .exe actualizada.
void RegisterDeepLinkScheme();

// Busca una instancia primaria ya corriendo y le reenvía la URI por
// WM_COPYDATA. Devuelve true si se reenvió (el caller debe salir).
bool ForwardDeepLinkToPrimary(const std::wstring& uri);

#endif  // RUNNER_DEEP_LINK_H_
