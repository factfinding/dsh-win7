/*
 * dsho.dll: Windows 8+ entry points that ONNX Runtime's onnxruntime.dll (sherpa-onnx-win-x64,
 * used by the experimental voice input) imports, for Windows 7.
 *
 * scripts/patch-imports.ps1 renames the DLL's kernel32.dll, dxgi.dll and api-ms-win-core-path-l1-1-0.dll
 * imports to dsho.dll (the name has to fit in "dxgi.dll"). The generated out/shim/dsho.def forwards
 * every other kernel32 function the DLL imports back to kernel32 (scripts/gen-forward-def.ps1) and
 * maps the six functions Windows 7 lacks to the implementations below. Each calls the real API when
 * the running Windows has it, so behavior on Windows 8+/10 is unchanged.
 *
 * Windows 7 fallbacks (ONNX Runtime 1.28 call sites in parentheses):
 *  - CreateFile2: CreateFileW with the extended parameters folded into its flags (reading models).
 *  - GetSystemTimePreciseAsFileTime: GetSystemTimeAsFileTime (same clock, coarser resolution).
 *  - GetProcessMitigationPolicy: Windows 7 cannot set any of these policies, so every one reads as
 *    off, except DEP, which is always on for 64-bit processes (device discovery checks the Win32k
 *    lockdown before enumerating adapters).
 *  - CreateDXGIFactory2: CreateDXGIFactory1 with the flags dropped; the debug flag has no DXGI 1.1
 *    equivalent. Interfaces newer than Windows 7's DXGI fail with E_NOINTERFACE (device discovery
 *    asks for IDXGIFactory6 and then skips GPU enumeration; inference runs on the CPU).
 *  - PathCchRemoveBackslash, PathCchRemoveFileSpec: implemented here for drive, UNC and \\?\ paths
 *    (directory of a model path).
 */
#include <windows.h>

#define DSH_PATHCCH_MAX_CCH 0x8000

typedef HANDLE(WINAPI *create_file2_fn)(LPCWSTR, DWORD, DWORD, DWORD, LPCREATEFILE2_EXTENDED_PARAMETERS);
typedef VOID(WINAPI *get_system_time_precise_fn)(LPFILETIME);
typedef BOOL(WINAPI *get_process_mitigation_policy_fn)(HANDLE, PROCESS_MITIGATION_POLICY, PVOID, SIZE_T);
typedef HRESULT(WINAPI *create_dxgi_factory2_fn)(UINT, REFIID, void **);
typedef HRESULT(WINAPI *create_dxgi_factory1_fn)(REFIID, void **);
typedef HRESULT(WINAPI *path_cch_fn)(PWSTR, size_t);

static INIT_ONCE resolve_once = INIT_ONCE_STATIC_INIT;
static INIT_ONCE dxgi_once = INIT_ONCE_STATIC_INIT;
static create_file2_fn real_create_file2;
static get_system_time_precise_fn real_get_system_time_precise;
static get_process_mitigation_policy_fn real_get_process_mitigation_policy;
static path_cch_fn real_path_cch_remove_backslash;
static path_cch_fn real_path_cch_remove_file_spec;
static create_dxgi_factory2_fn real_create_dxgi_factory2;
static create_dxgi_factory1_fn create_dxgi_factory1;

static FARPROC export_of(LPCWSTR module, LPCSTR name, DWORD flags) {
  HMODULE handle = LoadLibraryExW(module, NULL, flags);
  return handle == NULL ? NULL : GetProcAddress(handle, name);
}

static BOOL CALLBACK resolve(PINIT_ONCE once, PVOID parameter, PVOID *context) {
  (void)once; (void)parameter; (void)context;
  real_create_file2 = (create_file2_fn)export_of(L"kernel32.dll", "CreateFile2", 0);
  real_get_system_time_precise = (get_system_time_precise_fn)export_of(L"kernel32.dll", "GetSystemTimePreciseAsFileTime", 0);
  real_get_process_mitigation_policy = (get_process_mitigation_policy_fn)export_of(L"kernel32.dll", "GetProcessMitigationPolicy", 0);
  /* api-ms-win-core-path-l1-1-0 is implemented by KernelBase on Windows 8+. */
  real_path_cch_remove_backslash = (path_cch_fn)export_of(L"kernelbase.dll", "PathCchRemoveBackslash", 0);
  real_path_cch_remove_file_spec = (path_cch_fn)export_of(L"kernelbase.dll", "PathCchRemoveFileSpec", 0);
  return TRUE;
}

/* dxgi.dll is loaded only when a factory is requested, from System32 (KB2533623 provides the flag on Windows 7). */
static BOOL CALLBACK resolve_dxgi(PINIT_ONCE once, PVOID parameter, PVOID *context) {
  (void)once; (void)parameter; (void)context;
  real_create_dxgi_factory2 = (create_dxgi_factory2_fn)export_of(L"dxgi.dll", "CreateDXGIFactory2", LOAD_LIBRARY_SEARCH_SYSTEM32);
  create_dxgi_factory1 = (create_dxgi_factory1_fn)export_of(L"dxgi.dll", "CreateDXGIFactory1", LOAD_LIBRARY_SEARCH_SYSTEM32);
  return TRUE;
}

static void ensure_resolved(void) {
  InitOnceExecuteOnce(&resolve_once, resolve, NULL, NULL);
}

HANDLE WINAPI DshCreateFile2(LPCWSTR name, DWORD access, DWORD share, DWORD disposition, LPCREATEFILE2_EXTENDED_PARAMETERS parameters) {
  DWORD flags = 0;
  LPSECURITY_ATTRIBUTES security = NULL;
  HANDLE template_file = NULL;
  ensure_resolved();
  if (real_create_file2 != NULL) return real_create_file2(name, access, share, disposition, parameters);
  if (parameters != NULL) {
    if (parameters->dwSize < sizeof(*parameters)) {
      SetLastError(ERROR_INVALID_PARAMETER);
      return INVALID_HANDLE_VALUE;
    }
    flags = parameters->dwFileAttributes | parameters->dwFileFlags | parameters->dwSecurityQosFlags;
    security = parameters->lpSecurityAttributes;
    template_file = parameters->hTemplateFile;
  }
  return CreateFileW(name, access, share, security, disposition, flags, template_file);
}

VOID WINAPI DshGetSystemTimePreciseAsFileTime(LPFILETIME time) {
  ensure_resolved();
  if (real_get_system_time_precise != NULL) real_get_system_time_precise(time);
  else GetSystemTimeAsFileTime(time);
}

BOOL WINAPI DshGetProcessMitigationPolicy(HANDLE process, PROCESS_MITIGATION_POLICY policy, PVOID buffer, SIZE_T length) {
  ensure_resolved();
  if (real_get_process_mitigation_policy != NULL) return real_get_process_mitigation_policy(process, policy, buffer, length);
  if (buffer == NULL || length == 0) {
    SetLastError(ERROR_INVALID_PARAMETER);
    return FALSE;
  }
  ZeroMemory(buffer, length);
  if (policy == ProcessDEPPolicy && length >= sizeof(PROCESS_MITIGATION_DEP_POLICY)) {
    ((PROCESS_MITIGATION_DEP_POLICY *)buffer)->Enable = 1;
    ((PROCESS_MITIGATION_DEP_POLICY *)buffer)->Permanent = TRUE;
  }
  return TRUE;
}

HRESULT WINAPI DshCreateDXGIFactory2(UINT flags, REFIID riid, void **factory) {
  InitOnceExecuteOnce(&dxgi_once, resolve_dxgi, NULL, NULL);
  if (real_create_dxgi_factory2 != NULL) return real_create_dxgi_factory2(flags, riid, factory);
  if (factory == NULL) return E_INVALIDARG;
  *factory = NULL;
  if (create_dxgi_factory1 == NULL) return E_NOTIMPL;
  return create_dxgi_factory1(riid, factory);
}

/*
 * Root length of a path: "C:\" and "\" include their backslash, "C:" has none, and UNC roots
 * ("\\server\share", "\\?\UNC\server\share") stop before the backslash that follows the share.
 * Other "\\?\" forms keep only the prefix. Relative paths have no root.
 */
static size_t root_length(const WCHAR *path) {
  const WCHAR *p = path;
  int part;
  if (wcsncmp(p, L"\\\\?\\UNC\\", 8) == 0) p += 8;
  else if (wcsncmp(p, L"\\\\?\\", 4) == 0) {
    p += 4;
    if (((p[0] >= L'A' && p[0] <= L'Z') || (p[0] >= L'a' && p[0] <= L'z')) && p[1] == L':') return 4 + (p[2] == L'\\' ? 3 : 2);
    return 4;
  } else if (p[0] == L'\\' && p[1] == L'\\') p += 2;
  else if (((p[0] >= L'A' && p[0] <= L'Z') || (p[0] >= L'a' && p[0] <= L'z')) && p[1] == L':') return p[2] == L'\\' ? 3 : 2;
  else return p[0] == L'\\' ? 1 : 0;
  for (part = 0; part < 2 && *p != L'\0'; part++) {
    if (part == 1) p++;
    while (*p != L'\0' && *p != L'\\') p++;
  }
  return (size_t)(p - path);
}

/* Length of the string, or E_INVALIDARG when it is not terminated within size characters. */
static HRESULT checked_length(const WCHAR *path, size_t size, size_t *length) {
  if (path == NULL || size == 0 || size > DSH_PATHCCH_MAX_CCH) return E_INVALIDARG;
  for (*length = 0; *length < size; (*length)++) if (path[*length] == L'\0') return S_OK;
  return E_INVALIDARG;
}

HRESULT WINAPI DshPathCchRemoveBackslash(PWSTR path, size_t size) {
  size_t length;
  HRESULT result;
  ensure_resolved();
  if (real_path_cch_remove_backslash != NULL) return real_path_cch_remove_backslash(path, size);
  if (FAILED(result = checked_length(path, size, &length))) return result;
  if (length == 0 || path[length - 1] != L'\\' || length - 1 < root_length(path)) return S_FALSE;
  path[length - 1] = L'\0';
  return S_OK;
}

HRESULT WINAPI DshPathCchRemoveFileSpec(PWSTR path, size_t size) {
  size_t length, root, end;
  HRESULT result;
  ensure_resolved();
  if (real_path_cch_remove_file_spec != NULL) return real_path_cch_remove_file_spec(path, size);
  if (FAILED(result = checked_length(path, size, &length))) return result;
  root = root_length(path);
  /* Cut at the last backslash after the root, or back to the root when the last element follows it directly. */
  for (end = length; end > root && path[end - 1] != L'\\'; end--) {}
  if (end > root) end--;
  if (end == length) return S_FALSE;
  path[end] = L'\0';
  return S_OK;
}

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
  (void)reserved;
  if (reason == DLL_PROCESS_ATTACH) DisableThreadLibraryCalls(instance);
  return TRUE;
}
