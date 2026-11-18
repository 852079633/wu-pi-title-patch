$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..') -ErrorAction Stop

$focusedTests = @(
    [pscustomobject]@{ Package = 'terminal'; Test = 'tests::test_osc_title_updates_per_terminal_and_survives_reset' },
    [pscustomobject]@{ Package = 'terminal'; Test = 'tests::test_task_and_static_titles_take_priority_over_osc' },
    [pscustomobject]@{ Package = 'terminal_view'; Test = 'tests::test_tab_content_uses_custom_title' },
    [pscustomobject]@{ Package = 'terminal_view'; Test = 'tests::test_osc_title_updates_tab_and_respects_manual_titles' },
    [pscustomobject]@{ Package = 'terminal_view'; Test = 'tests::test_real_powershell_pty_title_reaches_terminal_tab' }
)

foreach ($focusedTest in $focusedTests) {
    Write-Output "RUNNING $($focusedTest.Package) $($focusedTest.Test)"
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = & cargo test --locked --package $focusedTest.Package --lib $focusedTest.Test -- --exact --nocapture 2>&1
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }
    foreach ($line in $output) { Write-Output $line }
    $outputText = ($output | ForEach-Object { $_.ToString() }) -join "`n"
    if ($exitCode -ne 0) { throw "Focused test failed with exit code ${exitCode}: $($focusedTest.Test)" }
    if ($outputText -notmatch '(?m)^running 1 test\s*$') {
        throw "Focused test did not run exactly one test: $($focusedTest.Test)"
    }
    if ($outputText -notmatch 'test result:\s+ok\.\s+1 passed;\s+0 failed\b') {
        throw "Focused test did not report exactly one passing test: $($focusedTest.Test)"
    }
    Write-Output "PASS $($focusedTest.Test)"
}

Write-Output "FOCUSED_TEST_COUNT=$($focusedTests.Count)"
Write-Output 'ALL_FOCUSED_TESTS=PASS'
