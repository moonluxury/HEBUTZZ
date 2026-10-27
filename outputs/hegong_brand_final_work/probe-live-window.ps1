param([string]$Executable='E:\zhengzhi\build\河工开物.exe',[string]$Label='before',[switch]$ClearIcons)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class LiveIconProbe {
 [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr w,uint msg,IntPtr wp,IntPtr lp);
 [DllImport("user32.dll",EntryPoint="GetClassLongPtrW")] public static extern IntPtr GetClassLongPtr(IntPtr w,int index);
 [DllImport("user32.dll")] public static extern uint GetDpiForWindow(IntPtr w);
 [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
 [DllImport("user32.dll")] public static extern bool DrawIconEx(IntPtr dc,int x,int y,IntPtr icon,int width,int height,uint step,IntPtr brush,uint flags);
}
'@
[LiveIconProbe]::SetProcessDpiAwarenessContext([IntPtr](-4)) | Out-Null
$taskWork='E:\zhengzhi\outputs\hegong_brand_final_work'
$env:APPDATA='E:\zhengzhi\.godot_appdata\brand-final-20261019'
$env:LOCALAPPDATA=Join-Path $env:APPDATA 'Local'
$env:TEMP=Join-Path $env:APPDATA 'Temp'
$env:TMP=$env:TEMP
$taskProcess=Start-Process -FilePath $Executable -ArgumentList @('--windowed','--resolution','640x420','--rendering-method','gl_compatibility','--max-fps','30','--log-file',"$taskWork\live-$Label.log") -WindowStyle Hidden -PassThru
try {
 $taskWindow=[IntPtr]::Zero
 for($taskAttempt=0;$taskAttempt -lt 40;$taskAttempt++){
  Start-Sleep -Milliseconds 250
  $taskProcess.Refresh()
  if($taskProcess.HasExited){throw "App exited early: $($taskProcess.ExitCode)"}
  $taskWindow=$taskProcess.MainWindowHandle
  if($taskWindow -ne [IntPtr]::Zero){break}
 }
 if($taskWindow -eq [IntPtr]::Zero){throw 'No application window found'}
 Start-Sleep -Milliseconds 1200
 Write-Output "Window DPI=$([LiveIconProbe]::GetDpiForWindow($taskWindow))"
 if($ClearIcons){
  [LiveIconProbe]::SendMessage($taskWindow,0x80,[IntPtr]0,[IntPtr]::Zero) | Out-Null
  [LiveIconProbe]::SendMessage($taskWindow,0x80,[IntPtr]1,[IntPtr]::Zero) | Out-Null
 }
 foreach($taskKind in @('small','big','small2','class-big','class-small')){
  $taskHandle=switch($taskKind){
   'small' {[LiveIconProbe]::SendMessage($taskWindow,0x7f,[IntPtr]0,[IntPtr]::Zero)}
   'big' {[LiveIconProbe]::SendMessage($taskWindow,0x7f,[IntPtr]1,[IntPtr]::Zero)}
   'small2' {[LiveIconProbe]::SendMessage($taskWindow,0x7f,[IntPtr]2,[IntPtr]::Zero)}
   'class-big' {[LiveIconProbe]::GetClassLongPtr($taskWindow,-14)}
   'class-small' {[LiveIconProbe]::GetClassLongPtr($taskWindow,-34)}
  }
  if($taskHandle -eq [IntPtr]::Zero){Write-Output "$taskKind has no handle";continue}
  $taskIcon=[Drawing.Icon]::FromHandle($taskHandle)
  $taskBitmap=$taskIcon.ToBitmap()
  $taskBitmap.Save((Join-Path $taskWork "live-$Label-$taskKind.png"),[Drawing.Imaging.ImageFormat]::Png)
  Write-Output "$taskKind=$($taskBitmap.Width)x$($taskBitmap.Height)"
  $taskBitmap.Dispose();$taskIcon.Dispose()
  if($taskKind -in @('big','small')){
   $taskDrawSize=if($taskKind -eq 'small'){16}else{32}
   $taskDrawBitmap=New-Object Drawing.Bitmap($taskDrawSize,$taskDrawSize)
   $taskGraphics=[Drawing.Graphics]::FromImage($taskDrawBitmap)
   $taskGraphics.Clear([Drawing.Color]::FromArgb(255,32,32,32))
   $taskDc=$taskGraphics.GetHdc()
   try{[LiveIconProbe]::DrawIconEx($taskDc,0,0,$taskHandle,$taskDrawSize,$taskDrawSize,0,[IntPtr]::Zero,3) | Out-Null}
   finally{$taskGraphics.ReleaseHdc($taskDc)}
   $taskGraphics.Dispose()
   $taskDrawBitmap.Save((Join-Path $taskWork "live-$Label-drawn-$taskKind.png"),[Drawing.Imaging.ImageFormat]::Png)
   $taskDrawBitmap.Dispose()
  }
 }
} finally {
 if(-not $taskProcess.HasExited){
  $taskProcess.CloseMainWindow() | Out-Null
  if(-not $taskProcess.WaitForExit(5000)){$taskProcess.Kill()}
 }
}
