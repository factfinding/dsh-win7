# Builds an ISO9660+Joliet image from a directory using the built-in IMAPI2 COM API.
param(
  [Parameter(Mandatory)] [string] $SourceDir,
  [Parameter(Mandatory)] [string] $IsoPath,
  [string] $VolumeName = 'TOVM'
)
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class IsoStreamWriter {
  public static void Write(object comStream, string path) {
    IStream s = (IStream)comStream;
    byte[] buf = new byte[1 << 20];
    IntPtr pRead = Marshal.AllocHGlobal(sizeof(int));
    try {
      using (FileStream fs = File.Create(path)) {
        while (true) {
          s.Read(buf, buf.Length, pRead);
          int n = Marshal.ReadInt32(pRead);
          if (n == 0) break;
          fs.Write(buf, 0, n);
        }
      }
    } finally {
      Marshal.FreeHGlobal(pRead);
    }
  }
}
'@

$fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
$fsi.FileSystemsToCreate = 3   # FsiFileSystemISO9660 | FsiFileSystemJoliet
$fsi.VolumeName = $VolumeName
$fsi.FreeMediaBlocks = 0       # no size limit; the default is a 650 MB CD
$fsi.Root.AddTree($SourceDir, $false)
$image = $fsi.CreateResultImage()
[IsoStreamWriter]::Write($image.ImageStream, $IsoPath)
Get-Item $IsoPath | Select-Object FullName, Length
