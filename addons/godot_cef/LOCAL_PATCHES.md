# Windows console behavior

Godot CEF 2.1.1 forces `enable-logging=stderr` in its browser and child process
startup callbacks (`crates/cef_app/src/lib.rs` and `browser_process.rs`). Chromium
creates a Windows console when `enable-logging` is present, even if its value is
changed to use file logging. Redirecting output in a test launcher can conceal
this behavior.

`tools/prepare_submission_runtime.py` prepares a separate
`bin/x86_64-pc-windows-msvc-quiet` runtime. It verifies the pinned upstream SHA-256
of both `gdcef.dll` and `gdcef_helper.exe`, then changes their single shared ASCII
literal from `enable-logging=stderr` to the equal-length `disable-logging=quiet`.
The switch value is ignored by Chromium; the switch disables its forced logging.
Executable instructions, section sizes, entry points, input handling, sandbox
flags, permissions and certificate checks are untouched. Godot's normal log
still records application errors. Original vendor files remain intact, including
those used by already-running instances.

This is a reproducible local binary patch, not a claim that the upstream release
has been rebuilt. The equivalent source change is removing the forced logging
switch at those startup call sites. Patch source and resulting binary hashes are
recorded in `runtime-manifest.json`. The installer applies the patch on a fresh
checkout; updating the vendor version requires reviewing and updating the pins.
The original MIT/CEF notices remain distributed.

Regression: `tools/check_submission_console.py --godot <GUI Godot executable>`
or `--exe <exported GUI executable>` launches without inherited stdio and checks
the application's process descendants. The old build reproduced a console in
this launch mode; the prepared runtime must render the editor with none.
