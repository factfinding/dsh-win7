/*
 * dshlo.dll: Windows 8+/10 entry points that libreoffice-kit.exe imports, for Windows 7.
 *
 * scripts/patch-imports.ps1 renames the exe's kernel32.dll, user32.dll and bcrypt.dll
 * imports to dshlo.dll. The generated out/shim/dshlo.def forwards every other function the
 * exe imports from those DLLs back to them (scripts/gen-forward-def.ps1), and maps the four
 * functions Windows 7 lacks to the implementations below. Each calls the real API when the
 * running Windows has it, so behavior on Windows 8+/10 is unchanged.
 *
 * Windows 7 fallbacks (libreoffice-kit renders and converts documents without windows):
 *  - GetCurrentPackageFullName: APPMODEL_ERROR_NO_PACKAGE, the answer for any unpackaged process.
 *  - GetSystemTimePreciseAsFileTime: GetSystemTimeAsFileTime (same clock, coarser resolution).
 *  - SetThreadDpiAwarenessContext: no per-thread DPI awareness exists, so nothing changes. It
 *    returns the context matching the process-wide awareness (SYSTEM_AWARE when IsProcessDPIAware,
 *    else UNAWARE) because callers treat NULL as failure; restoring with that value is a no-op too.
 *  - BCryptKeyDerivation: STATUS_NOT_SUPPORTED.
 */
#include <windows.h>

#ifndef APPMODEL_ERROR_NO_PACKAGE
#define APPMODEL_ERROR_NO_PACKAGE 15700L
#endif
#define DSH_STATUS_NOT_SUPPORTED ((LONG)0xC00000BBL)

typedef LONG(WINAPI *get_current_package_full_name_fn)(UINT32 *, PWSTR);
typedef VOID(WINAPI *get_system_time_precise_fn)(LPFILETIME);
typedef HANDLE(WINAPI *set_thread_dpi_awareness_context_fn)(HANDLE);
typedef LONG(WINAPI *bcrypt_key_derivation_fn)(HANDLE, PVOID, PUCHAR, ULONG, ULONG *, ULONG);
typedef BOOL(WINAPI *is_process_dpi_aware_fn)(void);

/* DPI_AWARENESS_CONTEXT_UNAWARE and DPI_AWARENESS_CONTEXT_SYSTEM_AWARE from windef.h. */
#define DSH_DPI_CONTEXT_UNAWARE ((HANDLE)(LONG_PTR)-1)
#define DSH_DPI_CONTEXT_SYSTEM_AWARE ((HANDLE)(LONG_PTR)-2)

static INIT_ONCE resolve_once = INIT_ONCE_STATIC_INIT;
static get_current_package_full_name_fn real_get_current_package_full_name;
static get_system_time_precise_fn real_get_system_time_precise;
static set_thread_dpi_awareness_context_fn real_set_thread_dpi_awareness_context;
static bcrypt_key_derivation_fn real_bcrypt_key_derivation;
static is_process_dpi_aware_fn is_process_dpi_aware;

static FARPROC export_of(LPCWSTR module, LPCSTR name) {
  HMODULE handle = LoadLibraryExW(module, NULL, 0);
  return handle == NULL ? NULL : GetProcAddress(handle, name);
}

static BOOL CALLBACK resolve(PINIT_ONCE once, PVOID parameter, PVOID *context) {
  (void)once; (void)parameter; (void)context;
  real_get_current_package_full_name = (get_current_package_full_name_fn)export_of(L"kernel32.dll", "GetCurrentPackageFullName");
  real_get_system_time_precise = (get_system_time_precise_fn)export_of(L"kernel32.dll", "GetSystemTimePreciseAsFileTime");
  real_set_thread_dpi_awareness_context = (set_thread_dpi_awareness_context_fn)export_of(L"user32.dll", "SetThreadDpiAwarenessContext");
  is_process_dpi_aware = (is_process_dpi_aware_fn)export_of(L"user32.dll", "IsProcessDPIAware");
  real_bcrypt_key_derivation = (bcrypt_key_derivation_fn)export_of(L"bcrypt.dll", "BCryptKeyDerivation");
  return TRUE;
}

static void ensure_resolved(void) {
  InitOnceExecuteOnce(&resolve_once, resolve, NULL, NULL);
}

LONG WINAPI DshGetCurrentPackageFullName(UINT32 *length, PWSTR name) {
  ensure_resolved();
  if (real_get_current_package_full_name != NULL) return real_get_current_package_full_name(length, name);
  if (length != NULL) *length = 0;
  return APPMODEL_ERROR_NO_PACKAGE;
}

VOID WINAPI DshGetSystemTimePreciseAsFileTime(LPFILETIME time) {
  ensure_resolved();
  if (real_get_system_time_precise != NULL) real_get_system_time_precise(time);
  else GetSystemTimeAsFileTime(time);
}

HANDLE WINAPI DshSetThreadDpiAwarenessContext(HANDLE context) {
  ensure_resolved();
  if (real_set_thread_dpi_awareness_context != NULL) return real_set_thread_dpi_awareness_context(context);
  if (context == NULL) return NULL;
  return is_process_dpi_aware != NULL && is_process_dpi_aware() ? DSH_DPI_CONTEXT_SYSTEM_AWARE : DSH_DPI_CONTEXT_UNAWARE;
}

LONG WINAPI DshBCryptKeyDerivation(HANDLE key, PVOID parameters, PUCHAR derived, ULONG derived_size, ULONG *result_size, ULONG flags) {
  ensure_resolved();
  if (real_bcrypt_key_derivation != NULL) return real_bcrypt_key_derivation(key, parameters, derived, derived_size, result_size, flags);
  if (result_size != NULL) *result_size = 0;
  return DSH_STATUS_NOT_SUPPORTED;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
  (void)reserved;
  if (reason == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(instance);
  return TRUE;
}
