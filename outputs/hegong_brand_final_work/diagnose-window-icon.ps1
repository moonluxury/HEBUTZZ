Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class IconNativeProbe {
 [DllImport("user32.dll",SetLastError=true)] public static extern IntPtr CreateIconFromResourceEx(byte[] data,uint size,bool icon,uint version,int width,int height,uint flags);
 [DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr icon);
 [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
 [DllImport("user32.dll")] public static extern uint GetDpiForSystem();
 [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
}
'@
[IconNativeProbe]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
$taskRoot='E:\zhengzhi\outputs\hegong_brand_final_work'
$taskBytes=[IO.File]::ReadAllBytes('E:\zhengzhi\assets\branding\hegong_zhigu_icon.ico')
$taskCount=[BitConverter]::ToUInt16($taskBytes,4)
$taskFrames=@()
for($taskIndex=0;$taskIndex -lt $taskCount;$taskIndex++){
 $taskEntry=6+$taskIndex*16
 $taskSize=if($taskBytes[$taskEntry] -eq 0){256}else{[int]$taskBytes[$taskEntry]}
 $taskLength=[BitConverter]::ToUInt32($taskBytes,$taskEntry+8)
 $taskOffset=[BitConverter]::ToUInt32($taskBytes,$taskEntry+12)
 $taskPayload=New-Object byte[] $taskLength
 [Array]::Copy($taskBytes,$taskOffset,$taskPayload,0,$taskLength)
 $taskEncoding=if($taskPayload[0] -eq 137){'PNG'}else{'DIB'}
 $taskFrames+=[PSCustomObject]@{Size=$taskSize;Encoding=$taskEncoding;Bytes=$taskLength}
 if($taskSize -in @(256,32,16)){
  $taskHandle=[IconNativeProbe]::CreateIconFromResourceEx($taskPayload,$taskLength,$true,0x30000,0,0,0x40)
  if($taskHandle -eq [IntPtr]::Zero){throw "Icon creation failed for $taskSize"}
  $taskIcon=[Drawing.Icon]::FromHandle($taskHandle)
  $taskBitmap=$taskIcon.ToBitmap()
  $taskBitmap.Save((Join-Path $taskRoot "win32-from-$taskSize.png"),[Drawing.Imaging.ImageFormat]::Png)
  Write-Output "CreateIconFromResourceEx: source=$taskSize output=$($taskBitmap.Width)x$($taskBitmap.Height)"
  $taskBitmap.Dispose();$taskIcon.Dispose();[IconNativeProbe]::DestroyIcon($taskHandle) | Out-Null
 }
}
Write-Output "DPI=$([IconNativeProbe]::GetDpiForSystem()), LARGE=$([IconNativeProbe]::GetSystemMetrics(11)), SMALL=$([IconNativeProbe]::GetSystemMetrics(49))"
$taskFrames | ConvertTo-Json
$taskPng=[IO.File]::ReadAllBytes('E:\zhengzhi\outputs\河工知谷_定稿方案_20261019\01_图形标识\河工知谷_彩色图形_透明_256.png')
$taskHandle=[IconNativeProbe]::CreateIconFromResourceEx($taskPng,$taskPng.Length,$true,0x30000,0,0,0x40)
if($taskHandle -ne [IntPtr]::Zero){
 $taskIcon=[Drawing.Icon]::FromHandle($taskHandle);$taskBitmap=$taskIcon.ToBitmap()
 $taskBitmap.Save((Join-Path $taskRoot 'win32-from-png256.png'),[Drawing.Imaging.ImageFormat]::Png)
 Write-Output "PNG source=256 output=$($taskBitmap.Width)x$($taskBitmap.Height)"
 $taskBitmap.Dispose();$taskIcon.Dispose();[IconNativeProbe]::DestroyIcon($taskHandle) | Out-Null
}
