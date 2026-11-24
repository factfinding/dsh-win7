/*
 * dshmu.dll: fopen and _wfopen for PyMuPDF's mupdfcpp64.dll on Windows 7.
 *
 * MuPDF creates output files with the exclusive-create mode "wb+x". The Universal CRT that Windows 7
 * gets from KB2999226 (10.0.10240) does not know 'x' and treats it as an invalid parameter, which
 * ends the process with 0xC0000417: Document.save(path) killed Python. Newer UCRTs accept it.
 *
 * scripts/patch-imports.ps1 renames the DLL's api-ms-win-crt-stdio-l1-1-0.dll import to dshmu.dll;
 * the .def that scripts/gen-forward-def.ps1 generates from its imports forwards every other stdio
 * function to ucrtbase. A mode without 'x' goes to ucrtbase's function unchanged. For a mode with 'x'
 * the file is created with CreateFile(CREATE_NEW), which fails with EEXIST when it exists, as 'x'
 * does, and is then opened with the mode minus 'x'. The FILE always comes from the process's
 * ucrtbase.dll, the CRT the caller's fwrite and fclose belong to, never from this DLL's static CRT.
 * Every Windows version takes this path, so the behaviour is the same on Windows 7 and later.
 */
#include <windows.h>
#include <errno.h>

#define DSH_MODE_MAX 64

typedef void *(__cdecl *wfopen_fn)(const wchar_t *, const wchar_t *);
typedef void *(__cdecl *fopen_fn)(const char *, const char *);
typedef int *(__cdecl *errno_fn)(void);

static HMODULE ucrt(void) {
  static HMODULE module;
  if (module == NULL) module = LoadLibraryW(L"ucrtbase.dll");
  return module;
}

static void set_errno(DWORD error) {
  errno_fn location = (errno_fn)GetProcAddress(ucrt(), "_errno");
  int value = EINVAL;
  if (error == ERROR_FILE_EXISTS || error == ERROR_ALREADY_EXISTS) value = EEXIST;
  else if (error == ERROR_ACCESS_DENIED || error == ERROR_SHARING_VIOLATION) value = EACCES;
  else if (error == ERROR_FILE_NOT_FOUND || error == ERROR_PATH_NOT_FOUND) value = ENOENT;
  if (location != NULL) *location() = value;
}

/* Copies mode without 'x' into out; returns 1 when 'x' was present and the copy fits. */
static int strip_x_w(const wchar_t *mode, wchar_t *out) {
  int found = 0, length = 0;
  for (; *mode != L'\0'; mode++) {
    if (*mode == L'x') { found = 1; continue; }
    if (length + 1 >= DSH_MODE_MAX) return 0;
    out[length++] = *mode;
  }
  out[length] = L'\0';
  return found;
}

static int strip_x_a(const char *mode, char *out) {
  int found = 0, length = 0;
  for (; *mode != '\0'; mode++) {
    if (*mode == 'x') { found = 1; continue; }
    if (length + 1 >= DSH_MODE_MAX) return 0;
    out[length++] = *mode;
  }
  out[length] = '\0';
  return found;
}

static int created(HANDLE file) {
  if (file == INVALID_HANDLE_VALUE) { set_errno(GetLastError()); return 0; }
  CloseHandle(file);
  return 1;
}

#define DSH_CREATE_NEW_ARGS GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, CREATE_NEW, FILE_ATTRIBUTE_NORMAL, NULL

void *__cdecl DshWfopen(const wchar_t *name, const wchar_t *mode) {
  wfopen_fn real = (wfopen_fn)GetProcAddress(ucrt(), "_wfopen");
  wchar_t stripped[DSH_MODE_MAX];
  if (real == NULL) { set_errno(ERROR_INVALID_FUNCTION); return NULL; }
  if (name == NULL || mode == NULL || !strip_x_w(mode, stripped)) return real(name, mode);
  if (!created(CreateFileW(name, DSH_CREATE_NEW_ARGS))) return NULL;
  return real(name, stripped);
}

void *__cdecl DshFopen(const char *name, const char *mode) {
  fopen_fn real = (fopen_fn)GetProcAddress(ucrt(), "fopen");
  char stripped[DSH_MODE_MAX];
  if (real == NULL) { set_errno(ERROR_INVALID_FUNCTION); return NULL; }
  if (name == NULL || mode == NULL || !strip_x_a(mode, stripped)) return real(name, mode);
  if (!created(CreateFileA(name, DSH_CREATE_NEW_ARGS))) return NULL;
  return real(name, stripped);
}
