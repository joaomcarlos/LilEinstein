param(
    [switch]$SkipInGame,
    [switch]$RequireInGame,
    [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot

Write-Host "Running Lua 5.2 unit suites..."
& lua52 (Join-Path $root "tests\run_all.lua")
if ($LASTEXITCODE -ne 0) {
    throw "Lua unit tests failed with exit code $LASTEXITCODE"
}

if ($SkipInGame) {
    Write-Host "In-game suite skipped by request."
    exit 0
}

$factorioCandidates = @()
if ($env:LILEINSTEIN_FACTORIO) {
    $factorioCandidates += $env:LILEINSTEIN_FACTORIO
}
$factorioCandidates += @(
    "F:\SteamLibrary\steamapps\common\Factorio\bin\x64\factorio.exe",
    "C:\Program Files (x86)\Steam\steamapps\common\Factorio\bin\x64\factorio.exe",
    "C:\Program Files\Steam\steamapps\common\Factorio\bin\x64\factorio.exe"
)
$factorio = $factorioCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $factorio) {
    $message = "Factorio executable not found. Set LILEINSTEIN_FACTORIO or use -SkipInGame."
    if ($RequireInGame) {
        throw $message
    }
    Write-Warning $message
    exit 0
}

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("LilEinstein-factorio-test-" + [guid]::NewGuid().ToString("N"))
$mods = Join-Path $stage "mods"
$writeData = Join-Path $stage "write-data"
$config = Join-Path $stage "config.ini"
$save = Join-Path $writeData "saves\lileinstein-smoke.zip"
$production = Join-Path $mods "LilEinstein_1.4.0"
$testMod = Join-Path $mods "lil-einstein-test_0.1.0"
$resultPath = Join-Path $writeData "script-output\lil_einstein_test_result.json"
$server = $null

New-Item -ItemType Directory -Force -Path $mods, $writeData, (Split-Path -Parent $save) | Out-Null
try {
    New-Item -ItemType Directory -Force -Path $production, $testMod | Out-Null
    $productionItems = @(
        "control.lua", "data.lua", "settings.lua", "info.json", "changelog.txt",
        "locale", "graphics", "lib", "model", "view", "data", "migrations"
    )
    foreach ($item in $productionItems) {
        $source = Join-Path $root $item
        if (Test-Path -LiteralPath $source) {
            Copy-Item -LiteralPath $source -Destination $production -Recurse -Force
        }
    }
    $testSource = Join-Path $root "tests\factorio\lil-einstein-test_0.1.0"
    Copy-Item -LiteralPath (Join-Path $testSource "info.json") -Destination $testMod -Force
    Copy-Item -LiteralPath (Join-Path $testSource "control.lua") -Destination $testMod -Force

    $factorioRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $factorio))
    $readData = Join-Path $factorioRoot "data"
    $configText = "[path]`r`nread-data=$readData`r`nwrite-data=$writeData`r`n"
    Set-Content -LiteralPath $config -Value $configText -Encoding UTF8

    Write-Host "Creating disposable Factorio save..."
    & $factorio --config $config --mod-directory $mods --create $save --map-gen-seed 20260811 --no-log-rotation
    if ($LASTEXITCODE -ne 0) {
        throw "Factorio save creation failed with exit code $LASTEXITCODE"
    }

    Write-Host "Waiting for disposable in-game assertions..."
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $resultPath) {
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not (Test-Path -LiteralPath $resultPath)) {
        throw "Timed out after $TimeoutSeconds seconds waiting for the in-game result"
    }

    $result = Get-Content -Raw -LiteralPath $resultPath | ConvertFrom-Json
    Write-Host ("In-game result: {0}; checks={1}; failed={2}; tick={3}" -f $result.status, $result.checks.Count, $result.failed, $result.tick)
    foreach ($check in $result.checks) {
        if (-not $check.pass) {
            Write-Host ("  FAIL {0}: {1}" -f $check.name, $check.detail)
        }
    }
    if ($result.status -ne "passed") {
        throw "In-game assertions failed"
    }
}
finally {
    if ($server -and -not $server.HasExited) {
        Stop-Process -Id $server.Id -Force
    }
    $lockPath = Join-Path $writeData ".lock"
    $releaseDeadline = (Get-Date).AddSeconds(15)
    while ((Test-Path -LiteralPath $lockPath) -and (Get-Date) -lt $releaseDeadline) {
        Start-Sleep -Milliseconds 250
    }
    $stageRoot = [System.IO.Path]::GetFullPath($stage)
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    if ($stageRoot.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $stageRoot)) {
        Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "All unit and in-game tests passed."
