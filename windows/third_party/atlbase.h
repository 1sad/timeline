// Minimal ATL compatibility shim for Flutter plugins that only need CW2A.
//
// flutter_local_notifications_windows includes <atlbase.h> solely to convert
// UTF-16 notification payloads to UTF-8. Visual Studio Build Tools does not
// install the optional ATL component by default, so provide the small piece
// the plugin actually uses instead of requiring that extra workload.
#pragma once

#include <windows.h>

#include <string>

#ifndef CW2A
class CW2A {
 public:
  explicit CW2A(PCWSTR source, UINT codePage = CP_ACP) {
    if (source == nullptr) return;
    const int length = WideCharToMultiByte(
        codePage, 0, source, -1, nullptr, 0, nullptr, nullptr);
    if (length <= 1) return;
    value_.resize(static_cast<size_t>(length));
    WideCharToMultiByte(
        codePage,
        0,
        source,
        -1,
        value_.data(),
        length,
        nullptr,
        nullptr);
    value_.resize(static_cast<size_t>(length - 1));
  }

  operator PCSTR() const { return value_.c_str(); }

 private:
  std::string value_;
};
#endif
