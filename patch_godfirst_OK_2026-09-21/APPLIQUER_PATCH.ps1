param(
    [string]$ProjectRoot = ""
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    Write-Host "FAIL: $Message" -ForegroundColor Red
    exit 1
}

function Pass([string]$Message) {
    Write-Host "PASS: $Message" -ForegroundColor Green
}

function Info([string]$Message) {
    Write-Host $Message -ForegroundColor Cyan
}

function Get-FullPathSafe([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }
    return [System.IO.Path]::GetFullPath($Value)
}

function Is-ProjectRoot([string]$PathValue) {
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return $false }
    $pubspec = Join-Path $PathValue "pubspec.yaml"
    $mainDart = Join-Path $PathValue "lib\main.dart"
    $mainPy = Join-Path $PathValue "backend\app\main.py"
    return ((Test-Path -LiteralPath $pubspec) -and (Test-Path -LiteralPath $mainDart) -and (Test-Path -LiteralPath $mainPy))
}

function Find-ProjectRoot([string]$StartPath) {
    if ([string]::IsNullOrWhiteSpace($StartPath)) { return $null }
    try {
        $current = Get-FullPathSafe $StartPath
    } catch {
        return $null
    }
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Is-ProjectRoot $current) { return $current }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or ($parent -eq $current)) { break }
        $current = $parent
    }
    return $null
}

function Contains-Text([string]$FilePath, [string]$Needle) {
    $content = Get-Content -LiteralPath $FilePath -Raw
    return $content.Contains($Needle)
}

$PatchDir = Get-FullPathSafe (Split-Path -Parent $PSCommandPath)
if ([string]::IsNullOrWhiteSpace($PatchDir)) {
    Fail "Impossible de trouver le dossier du patch."
}

$Root = $null
if (-not [string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $Root = Find-ProjectRoot $ProjectRoot
}
if ($null -eq $Root) {
    $Root = Find-ProjectRoot ((Get-Location).Path)
}
if ($null -eq $Root) {
    $Root = Find-ProjectRoot (Split-Path -Parent $PatchDir)
}
if ($null -eq $Root) {
    Fail "Racine du projet introuvable. Donne le chemin complet du projet en argument."
}

$Root = Get-FullPathSafe $Root
if ($Root -eq $PatchDir) {
    Fail "Le dossier du patch ne doit pas etre la racine du projet. Garde le patch dans un sous-dossier."
}

$pubspecPath = Join-Path $Root "pubspec.yaml"
$pubspec = Get-Content -LiteralPath $pubspecPath -Raw
if (-not $pubspec.Contains("name: edupro_flutter_web")) {
    Fail "pubspec.yaml ne correspond pas au projet attendu. Patch annule."
}

$files = @(
    "backend/app/main.py",
    "lib/data/models/plan_model.dart",
    "lib/shared/widgets/app_toast.dart",
    "lib/features/school/grades/canonical_grades_page.dart",
    "lib/core/utils/student_photo_picker_model.dart",
    "lib/core/utils/student_photo_picker_web.dart",
    "lib/features/school/students/student_photo_import_dialog.dart",
    "lib/features/school/students/students_page.dart",
    "lib/shared/widgets/app_header.dart",
    "test/teacher_workspace_test.dart"
)

Write-Host ""
Write-Host "PATCH GODFIRST-SCHOOL-MANAGMENT-SYSTEM" -ForegroundColor Yellow
Write-Host "Racine projet : $Root"
Write-Host "Dossier patch  : $PatchDir"
Write-Host ""

foreach ($rel in $files) {
    $windowsRel = $rel -replace '/', '\\'
    $src = Join-Path $PatchDir $windowsRel
    $dst = Join-Path $Root $windowsRel
    if (-not (Test-Path -LiteralPath $src)) {
        Fail "Fichier absent dans le patch: $rel"
    }
    if (-not (Test-Path -LiteralPath $dst)) {
        Fail "Fichier cible absent dans le projet: $rel"
    }
}

foreach ($rel in $files) {
    $windowsRel = $rel -replace '/', '\\'
    $src = Join-Path $PatchDir $windowsRel
    $dst = Join-Path $Root $windowsRel
    Copy-Item -LiteralPath $src -Destination $dst -Force
    Pass "remplace: $rel"
}

Write-Host ""
Info "Verification des marqueurs apres copie..."
$failures = 0

$checks = @(
    @{ File = "lib/data/models/plan_model.dart"; Text = "static int _intFromJson"; Label = "Plans: nombres String/num acceptes"; MustBeAbsent = $false },
    @{ File = "lib/shared/widgets/app_toast.dart"; Text = "Overlay.maybeOf(context, rootOverlay: true)"; Label = "Toasts: overlay racine"; MustBeAbsent = $false },
    @{ File = "lib/features/school/grades/canonical_grades_page.dart"; Text = "grade-presence-"; Label = "Notes: anciennes cles Note/Absent supprimees"; MustBeAbsent = $true },
    @{ File = "lib/features/school/grades/canonical_grades_page.dart"; Text = "Tous ont ete notes"; Label = "Notes: bouton Tous notes supprime"; MustBeAbsent = $true },
    @{ File = "lib/features/school/grades/canonical_grades_page.dart"; Text = "Tous ont été notés"; Label = "Notes: bouton Tous notes supprime accent"; MustBeAbsent = $true },
    @{ File = "backend/app/main.py"; Text = "return float(item.value) if item.value is not None else None"; Label = "Backend: absent ne vaut plus zero"; MustBeAbsent = $false },
    @{ File = "backend/app/main.py"; Text = "max_length=500"; Label = "Backend: import photo massif jusqu'a 500"; MustBeAbsent = $false },
    @{ File = "backend/app/main.py"; Text = '"image/heic"'; Label = "Backend: formats image elargis"; MustBeAbsent = $false },
    @{ File = "lib/core/utils/student_photo_picker_model.dart"; Text = "static const int maxBytes = 5 * 1024 * 1024"; Label = "Flutter: limite 5 Mo"; MustBeAbsent = $false },
    @{ File = "lib/core/utils/student_photo_picker_web.dart"; Text = "accept = 'image/*'"; Label = "Flutter Web: selection image/*"; MustBeAbsent = $false },
    @{ File = "lib/features/school/students/student_photo_import_dialog.dart"; Text = "validFiles"; Label = "Import photo: ignore les fichiers invalides"; MustBeAbsent = $false },
    @{ File = "lib/shared/widgets/app_header.dart"; Text = "_StudentPhotoAction"; Label = "Profil eleve: bouton modification photo supprime"; MustBeAbsent = $true }
)

foreach ($check in $checks) {
    $target = Join-Path $Root ($check.File -replace '/', '\\')
    if (-not (Test-Path -LiteralPath $target)) {
        Write-Host "FAIL: fichier absent pour verification: $($check.File)" -ForegroundColor Red
        $failures++
        continue
    }
    $hasText = Contains-Text $target $check.Text
    if ($check.MustBeAbsent) {
        if ($hasText) {
            Write-Host "FAIL: $($check.Label)" -ForegroundColor Red
            $failures++
        } else {
            Pass $check.Label
        }
    } else {
        if ($hasText) {
            Pass $check.Label
        } else {
            Write-Host "FAIL: $($check.Label)" -ForegroundColor Red
            $failures++
        }
    }
}

Write-Host ""
if ($failures -gt 0) {
    Fail "$failures verification(s) ont echoue. Envoie-moi la sortie complete."
}

Write-Host "PATCH APPLIQUE ET VERIFIE DANS LES SOURCES." -ForegroundColor Green
Write-Host "Tu peux maintenant relancer: flutter clean ; flutter pub get ; flutter run -d chrome --web-port 8080 --dart-define=API_BASE_URL=http://localhost:8000" -ForegroundColor Yellow
exit 0
