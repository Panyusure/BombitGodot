# Serialized test entry point.
#
# Parallel agents share one Godot project cache; running `godot --headless`
# concurrently corrupts .godot/ import state, so this queues behind a file lock.
#
# There is no pwsh on this machine (only Windows PowerShell 5.1), so call the
# .cmd shim next to this file:
#   cmd /c E:\BombitGodot\tools_test_locked.cmd              # test_core + test_play
#   cmd /c E:\BombitGodot\tools_test_locked.cmd test_core    # only test_core
#
# Pass/fail is decided by parsing CHECKS=/FAILURES= out of the output, NOT by the
# process exit code: the godot-ai addon writes a "CLIBOOT args=[]" line to stderr,
# which PowerShell 5.1 surfaces as NativeCommandError and would misreport failure.
#
# Keep this file ASCII-only: PowerShell 5.1 reads .ps1 in the OEM codepage, and
# non-ASCII bytes in comments can break parsing on a non-UTF8 code page.
param(
    [string]$Suite = 'all'
)

$ErrorActionPreference = 'Stop'
$root  = 'E:\BombitGodot'
$lock  = Join-Path $root '.godot_test.lock'
$godot = 'E:\Godot_v4.7.2-stable_win64.exe\Godot_v4.7.2-stable_win64_console.exe'

$deadline = (Get-Date).AddMinutes(15)
while ($true) {
    try {
        $fs = [System.IO.File]::Open($lock, [System.IO.FileMode]::CreateNew,
                                     [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $fs.Close()
        break
    } catch {
        if (Test-Path $lock) {
            $age = (Get-Date) - (Get-Item $lock).LastWriteTime
            if ($age.TotalMinutes -gt 8) {
                Remove-Item $lock -Force -ErrorAction SilentlyContinue
                continue
            }
        }
        if ((Get-Date) -gt $deadline) { Write-Output 'LOCK_TIMEOUT'; exit 3 }
        Start-Sleep -Seconds 3
    }
}

$failed = $false
try {
    $suites = if ($Suite -eq 'all') { @('test_core', 'test_play', 'test_art') } else { @($Suite) }
    foreach ($s in $suites) {
        Write-Output "=== $s ==="
        # Do not let a native stderr line escalate into a terminating error.
        $ErrorActionPreference = 'Continue'
        $out = & $godot --headless --path $root --script "res://tests/$s.gd" 2>&1 | Out-String
        $ErrorActionPreference = 'Stop'

        $summary = ($out -split "`n") | Where-Object { $_ -match '(CHECKS|FAILURES|CHECK|PASS|FAIL)\s*=' }
        if ($summary) { $summary | ForEach-Object { Write-Output $_.Trim() } }
        else { Write-Output ($out.Trim()) }

        if ($out -match 'FAILURES=0') {
            Write-Output "RESULT $s : PASS"
        } else {
            Write-Output "RESULT $s : FAIL"
            $failed = $true
        }
    }
} finally {
    Remove-Item $lock -Force -ErrorAction SilentlyContinue
}
if ($failed) { exit 1 } else { exit 0 }
