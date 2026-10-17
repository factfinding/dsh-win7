# Reports the Job of the current process: membership, limit flags and member pids (PowerShell 2.0, x64).
param([string] $Out)
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class OwnJob {
  [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool IsProcessInJob(IntPtr process, IntPtr job, out bool result);
  [DllImport("kernel32.dll", SetLastError = true)] static extern bool QueryInformationJobObject(IntPtr job, int infoClass, byte[] info, int length, out int returned);
  public static string Describe() {
    bool inJob;
    if (!IsProcessInJob(GetCurrentProcess(), IntPtr.Zero, out inJob)) return "IsProcessInJob failed " + Marshal.GetLastWin32Error();
    if (!inJob) return "not in a job";
    byte[] limits = new byte[144]; int n;
    string text = "in a job";
    if (QueryInformationJobObject(IntPtr.Zero, 9, limits, limits.Length, out n)) {
      uint flags = BitConverter.ToUInt32(limits, 16);
      text += string.Format("; LimitFlags=0x{0:X}", flags);
      if ((flags & 0x800) != 0) text += " BREAKAWAY_OK";
      if ((flags & 0x1000) != 0) text += " SILENT_BREAKAWAY_OK";
      if ((flags & 0x2000) != 0) text += " KILL_ON_JOB_CLOSE";
      if ((flags & 0x400) != 0) text += " DIE_ON_UNHANDLED_EXCEPTION";
    } else text += "; limits query failed " + Marshal.GetLastWin32Error();
    byte[] list = new byte[8 + 8 * 256];
    if (QueryInformationJobObject(IntPtr.Zero, 3, list, list.Length, out n)) {
      int count = BitConverter.ToInt32(list, 4);
      text += "; members:";
      for (int i = 0; i < count; i++) text += " " + BitConverter.ToInt64(list, 8 + 8 * i);
    } else text += "; pid list query failed " + Marshal.GetLastWin32Error();
    return text;
  }
}
"@
"pid $PID : " + [OwnJob]::Describe() | Out-File -FilePath $Out -Encoding ascii
