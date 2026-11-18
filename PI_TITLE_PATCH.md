# Pi session titles in Wu terminal tabs

> Unofficial fork of [Wu](https://github.com/dstrml/wu), not affiliated with or endorsed by the Wu maintainers.

This fork carries a Windows-validated patch that forwards terminal OSC titles to the corresponding Wu terminal tab, so a Pi session name can appear in the tab. It does not modify Pi, a user's database or settings, or an installed application automatically.

## Patch behavior

- Each terminal caches its own non-empty OSC title and emits a title-change event.
- Empty OSC titles and terminal title resets do not erase the last valid session title.
- Existing precedence remains: manual title, task title, static title override, OSC title, then the original process/working-directory title.
- A manually edited title remains in control until explicitly cleared. Confirming an untouched automatic title does not freeze it as a manual title.

The implementation and regression tests are limited to `crates/terminal/src/terminal.rs` and `crates/terminal_view/src/terminal_view.rs`. The Windows bundler is changed only to pass `--locked` to its four Cargo build commands.

## Patch baseline

`pi-title-1.3.0` is based on Wu commit `a4664065cecde801b73d35f26886dfc189835e85`, the 1.3.0 baseline used for local validation. The upstream `main` branch may move independently; do not assume this patch applies to a later version without checking whether Wu gained native support and then re-porting and testing the patch.

## Repeat this process for every Wu update

1. **Inspect upstream first.** Identify the exact new stable tag/commit and determine whether native Wu behavior now handles OSC titles and manual-title priority. If it does, do not carry a redundant patch.
2. **Create a versioned patch branch.** Base it on the exact upstream commit. Port only the title behavior and its focused tests; preserve upstream files, licenses, and unrelated changes.
3. **Run exact Windows tests.** Push the branch or open a PR to the default branch. CI resolves the selected source to one immutable SHA, runs formatting, and invokes `script/test-pi-title-patch.ps1`. Each test uses the full harness name with `--exact`; the script fails unless the harness reports exactly one passing test per entry.
4. **Review provenance and scope.** Confirm CI tested the intended SHA and inspect the diff for unrelated files, secrets, and machine-specific paths. The optional package job checks out that same tested SHA.
5. **Build only when needed.** Manually dispatch `Pi terminal-tab title patch`, select the tested ref, and enable `build_runtime`. The stable package job uses Wu's Windows bundler, pinned Rust 1.97.1, locked Cargo builds, two Cargo jobs, and a bounded timeout. It is not part of every push.
6. **Verify the portable artifact.** Download the seven-day Actions artifact. Check the JSON metadata's source commit, workflow run URL, included license materials, and SHA-256 against the ZIP. This is a portable runtime package, not an installer or GitHub Release.
7. **Smoke-test separately.** Extract the complete runtime layout into a new temporary directory and use a fresh `--user-data-dir`. Do not point it at production data or start it alongside the official Wu instance. Open a blank/test workspace, start a Pi session, and verify both the tab title and Pi's scroll bar/wheel behavior. CI cannot perform this native-GUI acceptance.
8. **Deploy only with explicit approval.** Treat installation as a separate, version-specific operation. After a verified backup and normal Wu shutdown, replace only files proven to match the candidate version; keep the database, settings, resources, CLI, and updater untouched unless the version comparison specifically requires otherwise. Never force-kill Wu or run an old deployment script against a new release. Retain a tested rollback path.

## Focused tests

The locally accepted baseline ran these exact Rust harness names, one at a time:

1. `tests::test_osc_title_updates_per_terminal_and_survives_reset`
2. `tests::test_task_and_static_titles_take_priority_over_osc`
3. `tests::test_tab_content_uses_custom_title`
4. `tests::test_osc_title_updates_tab_and_respects_manual_titles`
5. `tests::test_real_powershell_pty_title_reaches_terminal_tab`

The real PowerShell PTY test verifies an OSC title through Wu's terminal event path. These tests are not a substitute for a fresh GUI smoke test on every new Wu release or a Pi end-to-end check.

## Safe manual smoke-test example

Run this only after all Wu processes have exited normally. It extracts the full runtime and creates a fresh user-data directory; never substitute the real Wu data directory.

```powershell
$archives = @(Get-ChildItem -LiteralPath . -Filter 'Wu-*-x86_64-portable.zip')
if ($archives.Count -ne 1) { throw 'Place exactly one verified portable ZIP in the current directory.' }
$root = Join-Path $env:TEMP ('Wu-PiTitle-Smoke-' + [guid]::NewGuid().ToString('N'))
$runtime = Join-Path $root 'runtime'
$data = Join-Path $root 'data'
New-Item -Path $runtime, $data -ItemType Directory -Force | Out-Null
Expand-Archive -LiteralPath $archives[0].FullName -DestinationPath $runtime
& (Join-Path $runtime 'Wu.exe') --user-data-dir $data
```

Use a disposable/empty workspace, then check that the tab follows a Pi OSC session title and that scrolling still works. Close the smoke-test instance normally. Delete only the test directories when you have confirmed they contain no needed data.

## GitHub Actions

`.github/workflows/pi-title-patch.yml` runs the focused Windows tests on pushes to `pi-title-*` branches and pull requests targeting `pi-title-1.3.0`. The patch branch is the default branch so the manual workflow is discoverable; it can test a chosen branch, tag, or commit. Wait for push tests to finish before dispatching a build, since concurrent runs for the same branch are configured to cancel older runs.

The optional manual build uses Wu's official bundler and uploads a complete x64 runtime ZIP plus JSON provenance/SHA-256 metadata as a short-lived Actions artifact. The ZIP includes `conpty.dll`, x64 and ARM64 `OpenConsole.exe`, `amd_ags_x64.dll`, `bin\wu.exe`, `bin\wu`, tools, AppX files, file icons, upstream GPL/Apache files, generated `assets/licenses.md`, and `THIRD_PARTY_NOTICES.md`. It does not create a GitHub Release, synchronize upstream, install the application, or deploy to a machine. Workflow permissions are limited to `contents: read`; checkout credentials are not persisted.

## Licensing

Wu's README describes GPL-3.0-or-later licensing, with Apache-2.0 components where marked. This fork retains upstream license files and source notices. The Windows runtime's pinned ConPTY package declares MIT, and AMD AGS 6.3.0 carries an MIT `LICENSE.txt`; `THIRD_PARTY_NOTICES.md` includes both notices. The Cargo dependency license report is generated as `assets/licenses.md`. Recheck these sources and obligations whenever a bundled version changes; this notice is not legal advice.
