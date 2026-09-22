$ErrorActionPreference = 'Stop'

function Get-Sha256([string]$Path) {
    return (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLowerInvariant()
}

function Find-ProjectRoot([string]$Start) {
    $current = (Resolve-Path $Start).Path
    while ($true) {
        if ((Test-Path (Join-Path $current 'pubspec.yaml')) -and
            (Test-Path (Join-Path $current 'lib\main.dart')) -and
            (Test-Path (Join-Path $current 'backend\app\main.py'))) {
            $pubspec = Get-Content -Raw -Path (Join-Path $current 'pubspec.yaml')
            if ($pubspec -match 'name:\s*edupro_flutter_web') {
                return $current
            }
        }
        $parent = Split-Path -Parent $current
        if ($parent -eq $current -or [string]::IsNullOrWhiteSpace($parent)) {
            throw 'Racine du projet GODFIRST-SCHOOL-MANAGMENT-SYSTEM- introuvable. Lancez ce script depuis la racine du projet ou un sous-dossier.'
        }
        $current = $parent
    }
}

$PatchRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Find-ProjectRoot (Get-Location).Path

Write-Host "Projet détecté : $ProjectRoot"
Write-Host "Patch source   : $PatchRoot"

$files = @(
    @{ Path = 'backend/app/main.py'; OriginalSha256 = '2587fb664b243f6c5aa64fa5058d5213dbd5c3ac15a7838db5a996c8a42d1cd5'; PatchSha256 = '0c43697f3df69512c3fbcf8543d707e10e51f8b91cd7cbb7e50d2ec884e82f9d' }
    @{ Path = 'lib/data/models/plan_model.dart'; OriginalSha256 = 'c6f9da1360974100446f70c293032e9027dc669e39f21b5de98311efe6807d56'; PatchSha256 = 'fcad01a0fe4f8a4bfb306829fdda6c05abb7392c0f4d51028974222ab2f8ccc4' }
    @{ Path = 'lib/shared/widgets/app_toast.dart'; OriginalSha256 = '7fd511dfd6f8c0705669329a69e432b403e4f0c8736f02f00181f52de14c932c'; PatchSha256 = '343dae362234871f3b42b006c28948d297459103dda6495bf9562dd557005829' }
    @{ Path = 'lib/features/school/grades/canonical_grades_page.dart'; OriginalSha256 = 'dce4b06c7ecc133ce47439ae9e923cd08d0bf4bd4d60722880cd964dc347c771'; PatchSha256 = 'aedd412d5837238e7daf91285e8876a0ad049c20ff4caf3a7982f1dcd7bd1856' }
    @{ Path = 'lib/core/utils/student_photo_picker_model.dart'; OriginalSha256 = 'bca5c012c9e7a760646c15cc77d8a9cf31000f5a1f5d1bb42d9fa849a2720b55'; PatchSha256 = 'ab5a44cb3fb989e5e38d98e7eb7190179431552e88d600841539ca8ae10269f8' }
    @{ Path = 'lib/core/utils/student_photo_picker_web.dart'; OriginalSha256 = '63af4f93e56bcd8606459dc7e23a08ede1d0d06d4beb0e32f4096f035153c9f7'; PatchSha256 = '53b8c2f5a4c91d6460b72d0f0de4f4fd6d5acd84b574315d448125a36c8be8ac' }
    @{ Path = 'lib/features/school/students/student_photo_import_dialog.dart'; OriginalSha256 = '52b61d91d5639f141eb5359d3d89bf2b1e59f1d13e337b1aa0496a6b936836bb'; PatchSha256 = '132d231cebcd445805f3989dbdec760f151887c1a5d02eaf8cbf80ca1e22f93e' }
    @{ Path = 'lib/features/school/students/students_page.dart'; OriginalSha256 = '83681abb8987a1c1c67c5ccd73b23d17d4708ada5ccffec920f2a5a8955b1e82'; PatchSha256 = '62064fa8557ce9d986bbd14c8d7b21f72fde84817ff91378b11957c788500553' }
    @{ Path = 'lib/shared/widgets/app_header.dart'; OriginalSha256 = '8e98c16e83e36d44795500bda1af7fb5398e303ee1282273b206ba165bf05982'; PatchSha256 = '69949e0593ea28b4bec74ba30b059207fc3b1235515112032046e070dd034eb2' }
    @{ Path = 'test/teacher_workspace_test.dart'; OriginalSha256 = '832e355b7feaf9ee80e566d5c057997066a8aa29d37c1c569bed6058b26e574c'; PatchSha256 = '43ea4e5652ca579616c24d41587e70c1409387cdb7e35ef4ffd6072bd7d1b946' }
)

foreach ($item in $files) {
    $source = Join-Path $PatchRoot $item.Path
    $target = Join-Path $ProjectRoot $item.Path
    if (-not (Test-Path $source)) {
        throw "Fichier source du patch introuvable : $($item.Path)"
    }
    if (-not (Test-Path $target)) {
        throw "Fichier cible critique introuvable dans le projet : $($item.Path)"
    }
    $sourceHash = Get-Sha256 $source
    if ($sourceHash -ne $item.PatchSha256) {
        throw "Le fichier du patch ne correspond pas au contenu attendu : $($item.Path)"
    }
    $targetHash = Get-Sha256 $target
    if ($targetHash -eq $item.PatchSha256) {
        Write-Host "Déjà appliqué : $($item.Path)"
        continue
    }
    if ($targetHash -ne $item.OriginalSha256) {
        throw "Version locale inattendue pour $($item.Path). Le script refuse d'écraser silencieusement un fichier différent."
    }
}

$replaced = New-Object System.Collections.Generic.List[string]
foreach ($item in $files) {
    $source = Join-Path $PatchRoot $item.Path
    $target = Join-Path $ProjectRoot $item.Path
    $targetHash = Get-Sha256 $target
    if ($targetHash -eq $item.PatchSha256) { continue }
    $targetDirectory = Split-Path -Parent $target
    if (-not (Test-Path $targetDirectory)) {
        New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
    }
    Copy-Item -Path $source -Destination $target -Force
    $replaced.Add($item.Path) | Out-Null
}

Write-Host ''
Write-Host 'Fichiers remplacés :'
if ($replaced.Count -eq 0) {
    Write-Host 'Aucun fichier remplacé : patch déjà appliqué.'
} else {
    foreach ($path in $replaced) { Write-Host "- $path" }
}
Write-Host ''
Write-Host 'Patch terminé sans suppression, sans déplacement, sans base de données et sans copie globale.'
