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
$serverSettings = Join-Path $stage "server-settings.json"
$save = Join-Path $writeData "saves\lileinstein-smoke.zip"
$productionVersion = (Get-Content -Raw -LiteralPath (Join-Path $root "info.json") | ConvertFrom-Json).version
$production = Join-Path $mods ("LilEinstein_" + $productionVersion)
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
    Copy-Item -LiteralPath (Join-Path $testSource "data.lua") -Destination $testMod -Force
    Copy-Item -LiteralPath (Join-Path $testSource "control.lua") -Destination $testMod -Force

    $factorioRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $factorio))
    $readData = Join-Path $factorioRoot "data"
    $configText = "[path]`r`nread-data=$readData`r`nwrite-data=$writeData`r`n"
    Set-Content -LiteralPath $config -Value $configText -Encoding UTF8
    $serverSettingsValue = Get-Content -Raw -LiteralPath (Join-Path $readData "server-settings.example.json") |
        ConvertFrom-Json
    $serverSettingsValue.auto_pause = $false
    $serverSettingsValue.autosave_interval = 0
    $serverSettingsValue.visibility.public = $false
    $serverSettingsValue.visibility.lan = $false
    $serverSettingsValue | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $serverSettings -Encoding UTF8

    Write-Host "Creating disposable Factorio save..."
    $createArguments = @(
        "--config", $config,
        "--mod-directory", $mods,
        "--create", $save,
        "--map-gen-seed", "20260811",
        "--no-log-rotation"
    )
    $createArgumentText = ($createArguments | ForEach-Object {
        '"' + $_.Replace('"', '\"') + '"'
    }) -join ' '
    $createStdout = Join-Path $stage "factorio-create.stdout.log"
    $createStderr = Join-Path $stage "factorio-create.stderr.log"
    $creator = Start-Process -FilePath $factorio -ArgumentList $createArgumentText -PassThru -Wait -WindowStyle Hidden `
        -RedirectStandardOutput $createStdout -RedirectStandardError $createStderr
    if ($creator.ExitCode -ne 0) {
        $createOutput = if (Test-Path -LiteralPath $createStdout) {
            (Get-Content -Tail 80 -LiteralPath $createStdout) -join [Environment]::NewLine
        } else { "Factorio create stdout was not written." }
        $createError = if (Test-Path -LiteralPath $createStderr) {
            (Get-Content -Tail 80 -LiteralPath $createStderr) -join [Environment]::NewLine
        } else { "Factorio create stderr was not written." }
        throw "Factorio save creation failed with exit code $($creator.ExitCode).`n" +
            "STDOUT:`n$createOutput`nSTDERR:`n$createError"
    }

    $lockPath = Join-Path $writeData ".lock"
    $launchDeadline = (Get-Date).AddSeconds(15)
    while ((Test-Path -LiteralPath $lockPath) -and (Get-Date) -lt $launchDeadline) {
        Start-Sleep -Milliseconds 250
    }
    if (Test-Path -LiteralPath $lockPath) {
        throw "Factorio write-data lock was not released after save creation"
    }

    Write-Host "Starting disposable Factorio save headlessly..."
    $serverArguments = @(
        "--config", $config,
        "--mod-directory", $mods,
        "--start-server", $save,
        "--server-settings", $serverSettings,
        "--bind", "127.0.0.1:0",
        "--no-log-rotation"
    )
    $serverArgumentText = ($serverArguments | ForEach-Object {
        '"' + $_.Replace('"', '\"') + '"'
    }) -join ' '
    $serverStdout = Join-Path $stage "factorio-server.stdout.log"
    $serverStderr = Join-Path $stage "factorio-server.stderr.log"
    $server = Start-Process -FilePath $factorio -ArgumentList $serverArgumentText -PassThru -WindowStyle Hidden `
        -RedirectStandardOutput $serverStdout -RedirectStandardError $serverStderr

    Write-Host "Waiting for disposable in-game assertions..."
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $resultPath) {
            break
        }
        if ($server.HasExited) {
            $server.Refresh()
            $stdoutTail = if (Test-Path -LiteralPath $serverStdout) {
                (Get-Content -Tail 80 -LiteralPath $serverStdout) -join [Environment]::NewLine
            } else { "Factorio stdout was not created." }
            $stderrTail = if (Test-Path -LiteralPath $serverStderr) {
                (Get-Content -Tail 80 -LiteralPath $serverStderr) -join [Environment]::NewLine
            } else { "Factorio stderr was not created." }
            throw "Disposable Factorio server exited with code $($server.ExitCode) before writing results.`n" +
                "STDOUT:`n$stdoutTail`nSTDERR:`n$stderrTail"
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
