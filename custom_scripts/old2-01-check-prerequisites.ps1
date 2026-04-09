#!/usr/bin/env pwsh
# 01-check-prerequisites.ps1
# Verifie et installe les prerequis pour builder rpgmtranslate-qt.
# Setup identique au developpeur upstream: VS Build Tools 2026 + LLVM/clang-cl.
# A executer en PowerShell ADMIN.
#
# Pour chaque outil, le script:
#   - Tente une detection auto
#   - Si trouve: affiche le chemin et demande validation
#   - Si trouve pas: propose [1] specifier un chemin, [2] installer, [3] passer

$ErrorActionPreference = "Stop"

function Test-Command($cmd) {
    return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
}

# Demande a l'utilisateur de valider un chemin detecte, ou d'en fournir un autre
# Retourne le chemin valide, ou $null si skip
function Confirm-OrProvide {
    param(
        [string]$Name,
        [string]$DetectedPath,       # chemin detecte (peut etre vide)
        [string]$ValidationFile,     # fichier a verifier dans le chemin (ex: "bin\cl.exe")
        [scriptblock]$InstallAction  # action d'installation (peut etre $null)
    )

    if ($DetectedPath -and ($ValidationFile -eq "" -or (Test-Path (Join-Path $DetectedPath $ValidationFile)))) {
        Write-Host "[DETECTE] $Name" -ForegroundColor Green
        Write-Host "  Chemin: $DetectedPath" -ForegroundColor Gray
        $confirm = Read-Host "  Valider ? (O/n)"
        if ($confirm -eq "" -or $confirm -match "^[oOyY]") {
            return $DetectedPath
        }
    } else {
        Write-Host "[NON TROUVE] $Name" -ForegroundColor Yellow
    }

    # Pas detecte ou pas valide par l'utilisateur
    $options = @()
    $options += "[1] Specifier le chemin manuellement"
    if ($InstallAction) { $options += "[2] Installer automatiquement" }
    $options += "[0] Passer (ne rien faire)"

    Write-Host ""
    $options | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
    Write-Host ""

    $maxOpt = if ($InstallAction) { 2 } else { 1 }
    do {
        $choice = Read-Host "  Choix"
    } while ($choice -notin @("0", "1", "2")[0..$maxOpt])

    switch ($choice) {
        "1" {
            do {
                $manual = (Read-Host "  Chemin vers $Name").Trim('"').Trim("'")
                if ($ValidationFile -ne "" -and -not (Test-Path (Join-Path $manual $ValidationFile))) {
                    Write-Host "  '$ValidationFile' introuvable dans '$manual'. Reessaie." -ForegroundColor Red
                    $manual = $null
                }
            } while (-not $manual)
            Write-Host "  OK: $manual" -ForegroundColor Green
            return $manual
        }
        "2" {
            if ($InstallAction) {
                Write-Host "  Installation en cours..." -ForegroundColor Cyan
                & $InstallAction
            }
            return "__installed__"
        }
        "0" {
            Write-Host "  Passe." -ForegroundColor Gray
            return $null
        }
    }
}

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Verification des prerequis (setup upstream)" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# ══════════════════════════════════════════════════════════════════════
# 1. VS Build Tools 2026
# ══════════════════════════════════════════════════════════════════════
Write-Host "--- 1. Visual Studio Build Tools ---" -ForegroundColor Cyan
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsDetected = $null
$vsVersion = ""

if (Test-Path $vsWhere) {
    # -products * inclut les Build Tools (pas juste Community/Pro/Enterprise)
    $vsDetected = & $vsWhere -products * -latest -property installationPath 2>$null
    $vsVersion = & $vsWhere -products * -latest -property catalog_productLineVersion 2>$null
    $vsDisplay = & $vsWhere -products * -latest -property displayName 2>$null
}

$vsLabel = if ($vsDisplay) { "$vsDisplay (v$vsVersion)" } else { "Visual Studio Build Tools" }
$vsResult = Confirm-OrProvide `
    -Name $vsLabel `
    -DetectedPath $vsDetected `
    -ValidationFile "" `
    -InstallAction {
        winget install -e --id Microsoft.VisualStudio.BuildTools --source winget `
            --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
        Write-Host "  >> Redemarre ce script apres installation." -ForegroundColor Yellow
    }

if ($vsResult -and $vsResult -ne "__installed__") {
    Write-Host ""
}

# ══════════════════════════════════════════════════════════════════════
# 2. LLVM / clang-cl
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- 2. LLVM / clang-cl ---" -ForegroundColor Cyan
$llvmDetected = $null
$llvmPaths = @(
    "${env:ProgramFiles}\LLVM",
    "${env:ProgramFiles(x86)}\LLVM"
)
foreach ($p in $llvmPaths) {
    if (Test-Path "$p\bin\clang-cl.exe") {
        $llvmDetected = $p
        break
    }
}
# Aussi checker le PATH
if (-not $llvmDetected -and (Test-Command "clang-cl")) {
    $llvmDetected = Split-Path (Split-Path (Get-Command clang-cl).Source)
}

Confirm-OrProvide `
    -Name "LLVM (clang-cl)" `
    -DetectedPath $llvmDetected `
    -ValidationFile "bin\clang-cl.exe" `
    -InstallAction {
        winget install -e --id LLVM.LLVM --source winget
        Write-Host "  >> Relance ce script apres installation." -ForegroundColor Yellow
    } | Out-Null

# ══════════════════════════════════════════════════════════════════════
# 3. Git
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- 3. Git ---" -ForegroundColor Cyan
$gitDetected = $null
if (Test-Command "git") {
    $gitDetected = Split-Path (Split-Path (Get-Command git).Source)
}
$gitLabel = if ($gitDetected) { "Git - $(git --version)" } else { "Git" }

Confirm-OrProvide `
    -Name $gitLabel `
    -DetectedPath $gitDetected `
    -ValidationFile "" `
    -InstallAction {
        winget install -e --id Git.Git --source winget
    } | Out-Null

# ══════════════════════════════════════════════════════════════════════
# 4. CMake
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- 4. CMake ---" -ForegroundColor Cyan
$cmakeDetected = $null
if (Test-Command "cmake") {
    $cmakeDetected = Split-Path (Split-Path (Get-Command cmake).Source)
}
$cmakeLabel = if ($cmakeDetected) { "CMake - $(cmake --version | Select-Object -First 1)" } else { "CMake" }

Confirm-OrProvide `
    -Name $cmakeLabel `
    -DetectedPath $cmakeDetected `
    -ValidationFile "" `
    -InstallAction {
        winget install -e --id Kitware.CMake --source winget
    } | Out-Null

# ══════════════════════════════════════════════════════════════════════
# 5. Ninja
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- 5. Ninja ---" -ForegroundColor Cyan
$ninjaDetected = $null
if (Test-Command "ninja") {
    $ninjaDetected = Split-Path (Get-Command ninja).Source
}
$ninjaLabel = if ($ninjaDetected) { "Ninja - $(ninja --version)" } else { "Ninja" }

Confirm-OrProvide `
    -Name $ninjaLabel `
    -DetectedPath $ninjaDetected `
    -ValidationFile "" `
    -InstallAction {
        winget install -e --id Ninja-build.Ninja --source winget
    } | Out-Null

# ══════════════════════════════════════════════════════════════════════
# 6. Python
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- 6. Python ---" -ForegroundColor Cyan
$pythonDetected = $null
if (Test-Command "python") {
    $pythonDetected = Split-Path (Get-Command python).Source
}
$pythonLabel = if ($pythonDetected) { "Python - $(python --version 2>&1)" } else { "Python" }

Confirm-OrProvide `
    -Name $pythonLabel `
    -DetectedPath $pythonDetected `
    -ValidationFile "" `
    -InstallAction {
        winget install -e --id Python.Python.3.12 --source winget
    } | Out-Null

# ══════════════════════════════════════════════════════════════════════
# 7. Rust / Rustup
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- 7. Rust ---" -ForegroundColor Cyan
$rustDetected = $null
if (Test-Command "rustc") {
    $rustDetected = Split-Path (Get-Command rustc).Source
}
$rustLabel = if ($rustDetected) { "Rust - $(rustc --version)" } else { "Rust (rustup)" }

$rustResult = Confirm-OrProvide `
    -Name $rustLabel `
    -DetectedPath $rustDetected `
    -ValidationFile "" `
    -InstallAction {
        winget install -e --id Rustlang.Rustup --source winget
        Write-Host "  >> Ferme et rouvre PowerShell, puis relance ce script." -ForegroundColor Yellow
    }

# Configure MSVC target si Rust est present
if (Test-Command "rustup") {
    $targets = rustup target list --installed 2>$null
    if (-not ($targets -match "x86_64-pc-windows-msvc")) {
        Write-Host "  Configuration du target MSVC x64..." -ForegroundColor Yellow
        rustup default stable-x86_64-pc-windows-msvc
        rustup target add x86_64-pc-windows-msvc
    } else {
        Write-Host "  Target MSVC x64: OK" -ForegroundColor Green
    }
}

# ══════════════════════════════════════════════════════════════════════
# 8. cbindgen
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- 8. cbindgen ---" -ForegroundColor Cyan
$cbDetected = $null
if (Test-Command "cbindgen") {
    $cbDetected = Split-Path (Get-Command cbindgen).Source
}
$cbLabel = if ($cbDetected) { "cbindgen - $(cbindgen --version 2>$null)" } else { "cbindgen" }

Confirm-OrProvide `
    -Name $cbLabel `
    -DetectedPath $cbDetected `
    -ValidationFile "" `
    -InstallAction {
        cargo install cbindgen --version "0.29.2"
    } | Out-Null

# ══════════════════════════════════════════════════════════════════════
# 9. 7-Zip
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- 9. 7-Zip ---" -ForegroundColor Cyan
$szDetected = $null
$szPaths = @(
    "${env:ProgramFiles}\7-Zip",
    "${env:ProgramFiles(x86)}\7-Zip"
)
foreach ($p in $szPaths) {
    if (Test-Path "$p\7z.exe") { $szDetected = $p; break }
}
if (-not $szDetected -and (Test-Command "7z")) {
    $szDetected = Split-Path (Get-Command 7z).Source
}

Confirm-OrProvide `
    -Name "7-Zip" `
    -DetectedPath $szDetected `
    -ValidationFile "7z.exe" `
    -InstallAction {
        winget install -e --id 7zip.7zip --source winget
    } | Out-Null

# ══════════════════════════════════════════════════════════════════════
# 10. vcpkg
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- 10. vcpkg ---" -ForegroundColor Cyan
$vcpkgDetected = $null
$vcpkgDefault = "C:\vcpkg"
if (Test-Path "$vcpkgDefault\vcpkg.exe") {
    $vcpkgDetected = $vcpkgDefault
}

$vcpkgResult = Confirm-OrProvide `
    -Name "vcpkg" `
    -DetectedPath $vcpkgDetected `
    -ValidationFile "vcpkg.exe" `
    -InstallAction {
        $target = "C:\vcpkg"
        git clone https://github.com/microsoft/vcpkg.git $target
        & "$target\bootstrap-vcpkg.bat" -disableMetrics
    }

$vcpkgPath = if ($vcpkgResult -and $vcpkgResult -ne "__installed__") { $vcpkgResult } else { $vcpkgDefault }

# ══════════════════════════════════════════════════════════════════════
# 11. LibArchive (vcpkg, static)
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- 11. LibArchive (x64-windows-static) ---" -ForegroundColor Cyan
$archiveLib = "$vcpkgPath\installed\x64-windows-static\lib\archive.lib"
if (Test-Path $archiveLib) {
    Write-Host "[OK] LibArchive deja installe" -ForegroundColor Green
    Write-Host "  Chemin: $archiveLib" -ForegroundColor Gray
} else {
    Write-Host "[NON TROUVE] LibArchive" -ForegroundColor Yellow
    $install = Read-Host "  Installer via vcpkg ? (O/n)"
    if ($install -eq "" -or $install -match "^[oOyY]") {
        & "$vcpkgPath\vcpkg.exe" install libarchive:x64-windows-static
    }
}

# ══════════════════════════════════════════════════════════════════════
# Resume
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Verification terminee" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Prochaine etape :" -ForegroundColor White
Write-Host "  Si Qt statique n'est pas encore builde :" -ForegroundColor Gray
Write-Host "    .\02-build-qt-static.ps1" -ForegroundColor Yellow
Write-Host "  Sinon, builder le projet directement :" -ForegroundColor Gray
Write-Host "    .\03-build-rpgmtranslate.ps1" -ForegroundColor Yellow
