param([switch]$NoPause)

$ErrorActionPreference = 'Stop'

$ngrok = 'C:\Users\bouak\AppData\Local\Programs\ngrok\ngrok.exe'
if (-not (Test-Path -LiteralPath $ngrok)) {
    throw 'ngrok est introuvable. Relancez son installation avant de continuer.'
}

Write-Host ''
Write-Host 'Configuration securisee de ngrok' -ForegroundColor Cyan
Write-Host 'Le jeton est disponible dans le tableau de bord ngrok, rubrique Your Authtoken.'
$secureToken = Read-Host 'Collez votre authtoken ngrok (la saisie restera masquee)' -AsSecureString
$pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken)

try {
    $token = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    if ([string]::IsNullOrWhiteSpace($token)) {
        throw 'Aucun jeton saisi.'
    }
    & $ngrok config add-authtoken $token
    if ($LASTEXITCODE -ne 0) {
        throw 'ngrok a refuse le jeton. Verifiez-le dans votre tableau de bord.'
    }
    Write-Host ''
    Write-Host 'Compte ngrok associe avec succes.' -ForegroundColor Green
} finally {
    $token = $null
    if ($pointer -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    }
}

if (-not $NoPause) {
    Read-Host 'Appuyez sur Entree pour fermer cette fenetre'
}
