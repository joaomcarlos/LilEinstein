param(
    [switch]$RunInGame
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    & lua52 .\tests\run_all.lua
    if ($LASTEXITCODE -ne 0) {
        throw "Unit tests failed with exit code $LASTEXITCODE"
    }

    $hits = @{}
    foreach ($line in Get-Content -LiteralPath '.\coverage-unit-lines.tsv') {
        $parts = $line -split "`t"
        if ($parts.Count -eq 2) {
            $key = "$($parts[0])`t$($parts[1])"
            $hits[$key] = $true
        }
    }

    $total = 0
    $covered = 0
    $traceable_total = 0
    $traceable_covered = 0
    $uncovered = New-Object System.Collections.Generic.List[string]
    $traceable_uncovered = New-Object System.Collections.Generic.List[string]
    Get-ChildItem -LiteralPath '.\lib','.\model','.\view' -File -Filter '*.lua' -Recurse | ForEach-Object {
        $relative = $_.FullName.Substring((Get-Location).Path.Length + 1).Replace('\', '/')
        $source_lines = Get-Content -LiteralPath $_.FullName
        $instructions = & luac52 -l $_.FullName 2>&1
        $instruction_lines = @{}
        foreach ($instruction in $instructions) {
            if ($instruction -match '\[(\d+)\]') {
                $instruction_lines[[int]$Matches[1]] = $true
            }
        }
        foreach ($line_number in $instruction_lines.Keys) {
            $total++
            $source_line = $source_lines[$line_number - 1].Trim()
            # luac maps jump/table/call bookkeeping instructions to closing
            # syntax lines. Those lines have no independently executable Lua
            # statement; all source statements remain in the measured set.
            $is_non_executable_mapping = $source_line -match '^end$' -or $source_line -match '^[})]+[,]?$'
            if ($hits.ContainsKey("./$relative`t$line_number")) {
                $covered++
            } else {
                $uncovered.Add("$relative`:$line_number")
            }
            if (-not $is_non_executable_mapping) {
                $traceable_total++
                if ($hits.ContainsKey("./$relative`t$line_number")) {
                    $traceable_covered++
                } else {
                    $traceable_uncovered.Add("$relative`:$line_number")
                }
            }
        }
    }

    $percent = if ($total -eq 0) { 100 } else { [math]::Round(($covered * 100.0) / $total, 2) }
    $traceable_percent = if ($traceable_total -eq 0) { 100 } else { [math]::Round(($traceable_covered * 100.0) / $traceable_total, 2) }
    Write-Host ("Lua line-hook mappings (diagnostic): {0}/{1} ({2}%)" -f $covered, $total, $percent)
    Write-Host ("Lua executable-line coverage: {0}/{1} ({2}%)" -f $traceable_covered, $traceable_total, $traceable_percent)
    Write-Host ("Excluded from executable metric: {0} compiler-mapped syntax-only source mappings" -f ($total - $traceable_total))
    if ($uncovered.Count -gt 0) {
        Write-Host "Uncovered raw line mappings (first 200):"
        $uncovered | Select-Object -First 200 | ForEach-Object { Write-Host "  $_" }
    }
    if ($traceable_uncovered.Count -gt 0) {
        Write-Host "Uncovered executable lines (first 200):"
        $traceable_uncovered | Select-Object -First 200 | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "Uncovered executable lines: none"
    }
    if ($traceable_uncovered.Count -gt 0) {
        throw ("Executable-line coverage is below 100%; uncovered lines: {0}" -f $traceable_uncovered.Count)
    }
    if ($RunInGame) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1 -RequireInGame
        if ($LASTEXITCODE -ne 0) {
            throw "In-game tests failed with exit code $LASTEXITCODE"
        }
    }
}
finally {
    Pop-Location
}
