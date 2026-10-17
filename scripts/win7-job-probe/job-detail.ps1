# For each DSH-related process, starts own-job.ps1 as its child (so it inherits that process's Job) and prints
# what the probe reports about the Job. A second probe is started with CREATE_BREAKAWAY_FROM_JOB.
. C:\dsh-test\parent-spawn.ps1
$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$cmd = "$env:SystemRoot\System32\cmd.exe"
Get-WmiObject Win32_Process -Filter "Name='DeepSeek Harness.exe' or Name='pwsh.exe' or Name='node.exe' or Name='python.exe'" | Sort-Object ProcessId | ForEach-Object {
  $id = $_.ProcessId
  $line = $_.CommandLine
  if ($line.Length -gt 160) { $line = $line.Substring(0, 160) + '...' }
  "== pid $id parent $($_.ParentProcessId) $($_.Name)"
  "   $line"
  foreach ($probe in @(@{ name = 'inherit'; flags = 0 }, @{ name = 'breakaway'; flags = 0x01000000 })) {
    $out = "C:\dsh-test\job-$id-$($probe.name).out"
    Remove-Item $out, "$out.log" -ErrorAction SilentlyContinue
    $r = [ParentSpawn]::Run($id, "`"$cmd`" /c `"`"$ps`" -NoProfile -ExecutionPolicy Bypass -File C:\dsh-test\own-job.ps1 -Out $out > $out.log 2>&1`"", $probe.flags)
    "   [$($probe.name)] spawn: $r"
    if (Test-Path $out) { "   [$($probe.name)] " + (Get-Content $out) }
    if (Test-Path "$out.log") { Get-Content "$out.log" | ForEach-Object { "   [$($probe.name)] log: $_" } }
  }
}
