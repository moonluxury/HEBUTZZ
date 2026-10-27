param([ValidateSet('Windows','Android')][string]$Target='Windows')
$ErrorActionPreference='Stop'
$taskRoot='E:\zhengzhi'
$taskData=Join-Path $taskRoot '.godot_appdata\brand-final-20261019'
$taskLocal=Join-Path $taskData 'Local'
$taskTemp=Join-Path $taskData 'Temp'
$taskGodot=Join-Path $taskData 'Godot'
foreach($taskDir in @($taskData,$taskLocal,$taskTemp,$taskGodot)){New-Item -ItemType Directory -Path $taskDir -Force | Out-Null}
$taskSettings=Join-Path $taskGodot 'editor_settings-4.6.tres'
if(-not (Test-Path -LiteralPath $taskSettings)){
  $taskSettingsText=[IO.File]::ReadAllText('C:\Users\Legion\AppData\Roaming\Godot\editor_settings-4.6.tres')
  $taskSettingsText=[regex]::Replace($taskSettingsText,'(?m)^export/android/android_sdk_path = .*$', 'export/android/android_sdk_path = "E:/zhengzhi/android-sdk"')
  [IO.File]::WriteAllText($taskSettings,$taskSettingsText)
}
$taskSettingsText=[IO.File]::ReadAllText($taskSettings)
$taskSettingsText=[regex]::Replace($taskSettingsText,'(?m)^export/android/java_sdk_path = .*$', 'export/android/java_sdk_path = "E:/zhengzhi/.godot_appdata/brand-final-20261019/java-runtime"')
[IO.File]::WriteAllText($taskSettings,$taskSettingsText)
$taskTemplates=Join-Path $taskGodot 'export_templates'
$taskTemplateVersion=Join-Path $taskTemplates '4.6.2.stable'
New-Item -ItemType Directory -Path $taskTemplateVersion -Force | Out-Null
foreach($taskTemplateName in @('windows_release_x86_64.exe','windows_release_x86_64_console.exe','android_debug.apk','version.txt')){
  $taskTemplateFile=Join-Path $taskTemplateVersion $taskTemplateName
  if(-not (Test-Path -LiteralPath $taskTemplateFile)){
    Copy-Item -LiteralPath (Join-Path 'C:\Users\Legion\AppData\Roaming\Godot\export_templates\4.6.2.stable' $taskTemplateName) -Destination $taskTemplateFile
  }
}
$env:APPDATA=$taskData
$env:LOCALAPPDATA=$taskLocal
$env:TEMP=$taskTemp
$env:TMP=$taskTemp
$env:JAVA_HOME=Join-Path $taskData 'java-runtime'
$env:ANDROID_HOME=Join-Path $taskRoot 'android-sdk'
$env:ANDROID_SDK_ROOT=$env:ANDROID_HOME
$env:PATH=(Join-Path $env:JAVA_HOME 'bin')+';'+$env:PATH
$taskStage=Join-Path $taskRoot 'build\icon-refresh-20261019'
New-Item -ItemType Directory -Path $taskStage -Force | Out-Null
if($Target -eq 'Windows'){
  & 'F:\Godot_v4.6.2-stable_win64_console.exe' --headless --path $taskRoot --export-release 'Windows Desktop' (Join-Path $taskStage '河工开物.exe') *> (Join-Path $taskRoot 'outputs\hegong_brand_final_work\export-windows-local.log')
}else{
  & 'F:\Godot_v4.6.2-stable_win64_console.exe' --headless --path $taskRoot --export-debug 'Android' (Join-Path $taskStage '河工开物.apk') *> (Join-Path $taskRoot 'outputs\hegong_brand_final_work\export-android-local.log')
}
$taskResult=$LASTEXITCODE
Write-Output "Export $Target returned $taskResult"
exit $taskResult
