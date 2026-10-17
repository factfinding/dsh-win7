# Runs inside the Win7 VM (PowerShell 2.0). Resolves every import listed by
# dump-imports.ps1 with LoadLibrary/GetProcAddress and prints the missing ones.
param([string] $Tsv = 'C:\dsh-test\imports.tsv')
$sig = @"
[DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern IntPtr LoadLibraryW(string n);
[DllImport("kernel32.dll", CharSet=CharSet.Ansi, SetLastError=true)] public static extern IntPtr GetProcAddress(IntPtr h, string n);
[DllImport("kernel32.dll", SetLastError=true, EntryPoint="GetProcAddress")] public static extern IntPtr GetProcAddressOrd(IntPtr h, IntPtr ord);
"@
$k = Add-Type -MemberDefinition $sig -Name ImportCheck -Namespace Win7 -PassThru
$missing = 0; $checked = 0; $mods = @{}
foreach ($line in Get-Content $Tsv) {
  $p = $line.Split("`t"); $dll = $p[1]; $fn = $p[2]
  if (-not $mods.ContainsKey($dll)) {
    $mods[$dll] = $k::LoadLibraryW($dll)
    if ($mods[$dll] -eq [IntPtr]::Zero) { "MISSING DLL $dll" }
  }
  $h = $mods[$dll]
  if ($h -eq [IntPtr]::Zero) { $missing++; continue }
  if ($fn.StartsWith('#')) { $r = $k::GetProcAddressOrd($h, [IntPtr][int]$fn.Substring(1)) } else { $r = $k::GetProcAddress($h, $fn) }
  $checked++
  if ($r -eq [IntPtr]::Zero) { "MISSING $($p[0]) $dll!$fn"; $missing++ }
}
"checked $checked imports in $($mods.Count) DLLs, missing $missing"
