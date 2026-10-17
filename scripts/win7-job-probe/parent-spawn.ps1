# Starts a command as a child of another process (inheriting its Job) and waits for it (PowerShell 2.0, x64).
# Dot-source without -ParentId to load the [ParentSpawn] type only.
param([int] $ParentId, [string] $CommandLine)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class ParentSpawn {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  struct STARTUPINFO { public int cb; public string lpReserved, lpDesktop, lpTitle; public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags; public short wShowWindow, cbReserved2; public IntPtr lpReserved2, hStdInput, hStdOutput, hStdError; }
  [StructLayout(LayoutKind.Sequential)] struct STARTUPINFOEX { public STARTUPINFO StartupInfo; public IntPtr lpAttributeList; }
  [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr hProcess, hThread; public int dwProcessId, dwThreadId; }
  [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(int access, bool inherit, int pid);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool InitializeProcThreadAttributeList(IntPtr list, int count, int flags, ref IntPtr size);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool UpdateProcThreadAttribute(IntPtr list, int flags, IntPtr attribute, IntPtr value, IntPtr size, IntPtr previous, IntPtr returnSize);
  [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool CreateProcessW(string app, System.Text.StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit, int flags, IntPtr env, string cwd, ref STARTUPINFOEX si, out PROCESS_INFORMATION pi);
  [DllImport("kernel32.dll")] static extern int WaitForSingleObject(IntPtr handle, int ms);
  [DllImport("kernel32.dll")] static extern bool GetExitCodeProcess(IntPtr process, out uint code);
  public static string Run(int parentId, string commandLine, int flags) {
    IntPtr parent = OpenProcess(0x0080 | 0x0400, false, parentId);
    if (parent == IntPtr.Zero) return "OpenProcess failed " + Marshal.GetLastWin32Error();
    IntPtr size = IntPtr.Zero;
    InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref size);
    IntPtr list = Marshal.AllocHGlobal(size);
    if (!InitializeProcThreadAttributeList(list, 1, 0, ref size)) return "InitializeProcThreadAttributeList failed " + Marshal.GetLastWin32Error();
    IntPtr value = Marshal.AllocHGlobal(IntPtr.Size);
    Marshal.WriteIntPtr(value, parent);
    if (!UpdateProcThreadAttribute(list, 0, (IntPtr)0x00020000, value, (IntPtr)IntPtr.Size, IntPtr.Zero, IntPtr.Zero)) return "UpdateProcThreadAttribute failed " + Marshal.GetLastWin32Error();
    STARTUPINFOEX si = new STARTUPINFOEX();
    si.StartupInfo.cb = Marshal.SizeOf(typeof(STARTUPINFOEX));
    si.lpAttributeList = list;
    // The child runs in the parent's session; the creator's (session 0) desktop is not reachable from there.
    si.StartupInfo.lpDesktop = "winsta0\\default";
    PROCESS_INFORMATION pi;
    // EXTENDED_STARTUPINFO_PRESENT | CREATE_NO_WINDOW | extra flags
    if (!CreateProcessW(null, new System.Text.StringBuilder(commandLine), IntPtr.Zero, IntPtr.Zero, false, 0x00080000 | 0x08000000 | flags, IntPtr.Zero, null, ref si, out pi)) return "CreateProcessW failed " + Marshal.GetLastWin32Error();
    int wait = WaitForSingleObject(pi.hProcess, 60000);
    uint code;
    GetExitCodeProcess(pi.hProcess, out code);
    return "child pid " + pi.dwProcessId + " wait " + wait + " exit 0x" + code.ToString("X");
  }
}
"@
if ($ParentId) { [ParentSpawn]::Run($ParentId, $CommandLine, 0) }
