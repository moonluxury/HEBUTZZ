extends Node
## Windows CurrentUser DPAPI. Secret bytes travel over pipes, never command arguments.
const LIMIT := 32768
const TIMEOUT_MSEC := 10000
const HELPER := """
$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = New-Object System.Text.UTF8Encoding($false)
[Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false)
try {
    Add-Type -AssemblyName System.Security
    $request = [Console]::ReadLine() | ConvertFrom-Json
    $bytes = [Convert]::FromBase64String($request.data)
    $entropy = [Text.Encoding]::UTF8.GetBytes('HEGONG_LOCAL_LOGIN_V1')
    $scope = [Security.Cryptography.DataProtectionScope]::CurrentUser
    if ($request.mode -eq 'protect') {
        $result = [Security.Cryptography.ProtectedData]::Protect($bytes, $entropy, $scope)
    } elseif ($request.mode -eq 'unprotect') {
        $result = [Security.Cryptography.ProtectedData]::Unprotect($bytes, $entropy, $scope)
    } else { throw 'Invalid operation' }
    [Console]::WriteLine([Convert]::ToBase64String($result))
} catch { [Console]::WriteLine('!') }
"""
var active: Dictionary = {}

func supported() -> bool:
	return OS.get_name() == "Windows" and FileAccess.file_exists(_executable())

func _executable() -> String:
	return OS.get_environment("SystemRoot").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")

func transform(bytes: PackedByteArray, protect: bool) -> PackedByteArray:
	if not supported() or bytes.is_empty() or bytes.size() > LIMIT:
		return PackedByteArray()
	var process := OS.execute_with_pipe(_executable(), PackedStringArray([
		"-NoLogo", "-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-Command", HELPER]), false)
	if process.is_empty(): return PackedByteArray()
	var pid: int = process.pid
	active[pid] = process
	var pipe: FileAccess = process.stdio
	pipe.store_line(JSON.stringify({"mode": "protect" if protect else "unprotect", "data": Marshalls.raw_to_base64(bytes)}))
	pipe.flush()
	var received := PackedByteArray()
	var deadline := Time.get_ticks_msec() + TIMEOUT_MSEC
	while Time.get_ticks_msec() < deadline:
		var chunk := pipe.get_buffer(LIMIT)
		received.append_array(chunk)
		# Drain diagnostics without exposing any process input/output to application logs.
		process.stderr.get_buffer(LIMIT)
		if received.size() > LIMIT or received.has(10): break
		if not OS.is_process_running(pid) and chunk.is_empty(): break
		await get_tree().process_frame
	_close(process)
	active.erase(pid)
	var encoded := received.get_string_from_utf8().strip_edges()
	if encoded.is_empty() or encoded == "!" or encoded.length() > LIMIT: return PackedByteArray()
	var pattern := RegEx.new()
	pattern.compile("^[A-Za-z0-9+/]+={0,2}$")
	if encoded.length() % 4 != 0 or pattern.search(encoded) == null: return PackedByteArray()
	return Marshalls.base64_to_raw(encoded)

func _close(process: Dictionary) -> void:
	if OS.is_process_running(process.pid): OS.kill(process.pid)
	process.stdio.close()
	process.stderr.close()

func _exit_tree() -> void:
	for process in active.values(): _close(process)
	active.clear()
