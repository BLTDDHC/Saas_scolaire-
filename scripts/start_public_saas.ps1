$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$backend = Join-Path $projectRoot 'backend'
$python = Join-Path $backend '.venv\Scripts\python.exe'
$ngrok = 'C:\Users\bouak\AppData\Local\Programs\ngrok\ngrok.exe'
$flutter = 'C:\Users\bouak\flutter\bin\flutter.bat'
$backendProcess = $null
$ngrokProcess = $null

if (-not (Test-Path -LiteralPath $python)) {
    throw 'Python du projet est introuvable.'
}
if (-not (Test-Path -LiteralPath $ngrok)) {
    throw 'ngrok est introuvable.'
}
if (-not (Test-Path -LiteralPath $flutter)) {
    throw 'Flutter est introuvable.'
}

& $ngrok config check 2>$null | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Le compte ngrok doit etre associe une seule fois.' -ForegroundColor Yellow
    & (Join-Path $PSScriptRoot 'configure_ngrok.ps1') -NoPause
    & $ngrok config check 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'La configuration ngrok reste invalide.'
    }
}

try {
    $webBuild = Join-Path $projectRoot 'build\web\main.dart.js'
    $sourceFiles = @(
        Get-ChildItem -LiteralPath (Join-Path $projectRoot 'lib') -Recurse -File
        Get-ChildItem -LiteralPath (Join-Path $projectRoot 'web') -Recurse -File
        Get-Item -LiteralPath (Join-Path $projectRoot 'pubspec.yaml')
        Get-Item -LiteralPath (Join-Path $projectRoot 'pubspec.lock')
    )
    $latestSource = ($sourceFiles | Measure-Object LastWriteTime -Maximum).Maximum
    $mustBuild = -not (Test-Path -LiteralPath $webBuild)
    if (-not $mustBuild) {
        $mustBuild = $latestSource -gt (Get-Item -LiteralPath $webBuild).LastWriteTime
    }
    if ($mustBuild) {
        Write-Host 'Construction de la version Web actuelle...' -ForegroundColor Cyan
        & $flutter build web --release --pwa-strategy=none
        if ($LASTEXITCODE -ne 0) {
            throw 'La construction Flutter Web a echoue.'
        }
    }

    try {
        $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/health' -TimeoutSec 2
    } catch {
        $backendProcess = Start-Process `
            -FilePath $python `
            -ArgumentList '-m', 'uvicorn', 'app.main:app', '--host', '127.0.0.1', '--port', '8000' `
            -WorkingDirectory $backend `
            -WindowStyle Hidden `
            -PassThru

        $health = $null
        for ($attempt = 0; $attempt -lt 40; $attempt++) {
            Start-Sleep -Milliseconds 500
            try {
                $health = Invoke-RestMethod -Uri 'http://127.0.0.1:8000/health' -TimeoutSec 2
                break
            } catch {
                if ($backendProcess.HasExited) {
                    throw 'FastAPI a quitte pendant son demarrage.'
                }
            }
        }
    }

    if ($null -eq $health -or $health.status -ne 'ok') {
        throw 'Le health check FastAPI ne repond pas correctement.'
    }

    $ngrokLog = Join-Path $env:TEMP 'godfirst-ngrok.log'
    $ngrokErrorLog = Join-Path $env:TEMP 'godfirst-ngrok-error.log'
    $ngrokProcess = Start-Process `
        -FilePath $ngrok `
        -ArgumentList 'http', '8000', '--log=stdout', '--log-format=json' `
        -WindowStyle Hidden `
        -RedirectStandardOutput $ngrokLog `
        -RedirectStandardError $ngrokErrorLog `
        -PassThru

    $publicUrl = $null
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        Start-Sleep -Milliseconds 500
        if ($ngrokProcess.HasExited) {
            $details = if (Test-Path -LiteralPath $ngrokErrorLog) {
                Get-Content -LiteralPath $ngrokErrorLog -Raw
            } else { '' }
            throw "ngrok a quitte pendant son demarrage. $details"
        }
        try {
            $tunnels = Invoke-RestMethod -Uri 'http://127.0.0.1:4040/api/tunnels' -TimeoutSec 2
            $publicUrl = ($tunnels.tunnels | Where-Object { $_.proto -eq 'https' } | Select-Object -First 1).public_url
            if ($publicUrl) { break }
        } catch { }
    }
    if (-not $publicUrl) {
        throw 'ngrok fonctionne mais son adresse publique est introuvable.'
    }

    $ngrokHeaders = @{ 'ngrok-skip-browser-warning' = 'true' }
    $publicHealth = Invoke-RestMethod `
        -Uri "$publicUrl/api/v1/health" `
        -Headers $ngrokHeaders `
        -UserAgent 'GODFIRST-HealthCheck/1.0' `
        -TimeoutSec 20
    if ($publicHealth.status -ne 'ok') {
        throw 'Le health check public ne repond pas correctement.'
    }

    Set-Clipboard -Value $publicUrl
    Write-Host ''
    Write-Host 'SAAS DISPONIBLE SUR TELEPHONE ET PC' -ForegroundColor Green
    Write-Host $publicUrl -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Le lien a ete copie dans le presse-papiers.' -ForegroundColor Green
    Write-Host 'Partagez exactement ce lien HTTPS et gardez cette fenetre ouverte.' -ForegroundColor Yellow
    Write-Host 'Appuyez sur Entree pour arreter proprement le tunnel.'
    Read-Host
} finally {
    if ($null -ne $ngrokProcess -and -not $ngrokProcess.HasExited) {
        Stop-Process -Id $ngrokProcess.Id
    }
    if ($null -ne $backendProcess -and -not $backendProcess.HasExited) {
        Stop-Process -Id $backendProcess.Id
    }
}
