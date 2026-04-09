#!/usr/bin/env pwsh
# 01-check-prerequisites.ps1
# Verifie et installe les prerequis pour builder rpgmtranslate-qt.
# Setup identique au developpeur upstream: VS Build Tools 2026 + LLVM/clang-cl.
# A executer en PowerShell ADMIN.

$ErrorActionPreference = "Stop"

function Test-Command($cmd) {
    return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
}

function Write-Status($name, $ok, $detail) {
    $icon = if ($ok) { "[OK]" } else { "[MANQUANT]" }
    $color = if ($ok) { "Green" } else { "Red" }
    Write-Host "$icon $name" -ForegroundColor $color -NoNewline
    if ($detail) { Write-Host " - $detail" } else { Write-Host "" }
}

Write-Host ""
Write-Host "=== Verification des prerequis (setup upstream) ===" -ForegroundColor Cyan
Write-Host ""

# ── 1. VS Build Tools 2026 ──────────────────────────────────────────
# Le dev upstream utilise MSVC Build Tools 2026 (v18.x) pour le support C23.
# winget id: Microsoft.VisualStudio.BuildTools (installe la derniere version, donc 2026)
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$hasVS = $false
$vsVersion = ""
if (Test-Path $vsWhere) {
    $vsInstall = & $vsWhere -latest -property installationPath 2>$null
    $vsVersion = & $vsWhere -latest -property catalog_productLineVersion 2>$null
    if ($vsInstall -and (Test-Path "$vsInstall\VC\Auxiliary\Build\vcvarsall.bat")) {
        $hasVS = $true
    }
}
Write-Status "Visual Studio Build Tools" $hasVS $(if ($hasVS) { "$vsVersion - $vsInstall" })
if (-not $hasVS) {
    Write-Host "  Installation de VS Build Tools 2026..." -ForegroundColor Yellow
    winget install -e --id Microsoft.VisualStudio.BuildTools --source winget `
        --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
    Write-Host "  >> Redemarre ce script apres installation." -ForegroundColor Yellow
} elseif ($vsVersion -and [int]$vsVersion -lt 2026) {
    Write-Host "  ATTENTION: Tu as VS $vsVersion. Le dev upstream utilise 2026." -ForegroundColor Yellow
    Write-Host "  Pour mettre a jour: winget upgrade --id Microsoft.VisualStudio.BuildTools" -ForegroundColor Yellow
    Write-Host "  Ou installe VS Build Tools 2026 via Visual Studio Installer." -ForegroundColor Yellow
}

# ── 2. Git ───────────────────────────────────────────────────────────
$hasGit = Test-Command "git"
Write-Status "Git" $hasGit $(if ($hasGit) { (git --version) })
if (-not $hasGit) {
    Write-Host "  Installation..." -ForegroundColor Yellow
    winget install -e --id Git.Git --source winget
}

# ── 3. CMake ─────────────────────────────────────────────────────────
$hasCMake = Test-Command "cmake"
$cmakeVer = if ($hasCMake) { (cmake --version | Select-Object -First 1) } else { "" }
Write-Status "CMake" $hasCMake $cmakeVer
if (-not $hasCMake) {
    Write-Host "  CMake est normalement inclus avec VS Build Tools." -ForegroundColor Yellow
    Write-Host "  Sinon: winget install -e --id Kitware.CMake --source winget" -ForegroundColor Yellow
}

# ── 4. Ninja ─────────────────────────────────────────────────────────
$hasNinja = Test-Command "ninja"
Write-Status "Ninja" $hasNinja $(if ($hasNinja) { (ninja --version) })
if (-not $hasNinja) {
    Write-Host "  Installation..." -ForegroundColor Yellow
    winget install -e --id Ninja-build.Ninja --source winget
}

# ── 5. LLVM / clang-cl ──────────────────────────────────────────────
# Le dev upstream utilise clang-cl comme compilateur pour la compatibilite
# __uint128_t et C23.
$hasClangCl = Test-Command "clang-cl"
if (-not $hasClangCl) {
    $llvmPaths = @(
        "${env:ProgramFiles}\LLVM\bin\clang-cl.exe",
        "${env:ProgramFiles(x86)}\LLVM\bin\clang-cl.exe"
    )
    foreach ($p in $llvmPaths) {
        if (Test-Path $p) { $hasClangCl = $true; break }
    }
}
$clangVer = ""
if ($hasClangCl) {
    $clangVer = (& clang-cl --version 2>$null | Select-Object -First 1) 2>$null
    if (-not $clangVer) { $clangVer = "found" }
}
Write-Status "LLVM / clang-cl" $hasClangCl $clangVer
if (-not $hasClangCl) {
    Write-Host "  Installation..." -ForegroundColor Yellow
    winget install -e --id LLVM.LLVM --source winget
    Write-Host "  >> Relance ce script apres installation pour verifier le PATH." -ForegroundColor Yellow
}

# ── 6. Python ────────────────────────────────────────────────────────
# Necessaire pour builder Qt from source.
$hasPython = Test-Command "python"
Write-Status "Python" $hasPython $(if ($hasPython) { (python --version 2>&1) })
if (-not $hasPython) {
    Write-Host "  Installation..." -ForegroundColor Yellow
    winget install -e --id Python.Python.3.12 --source winget
}

# ── 7. Rust / Rustup ────────────────────────────────────────────────
$hasRustup = Test-Command "rustup"
$hasRustc = Test-Command "rustc"
Write-Status "Rust (rustup)" $hasRustup $(if ($hasRustc) { (rustc --version) })
if (-not $hasRustup) {
    Write-Host "  Installation..." -ForegroundColor Yellow
    winget install -e --id Rustlang.Rustup --source winget
    Write-Host "  >> Ferme et rouvre PowerShell, puis relance ce script." -ForegroundColor Yellow
}

# ── 8. Rust MSVC target ─────────────────────────────────────────────
if ($hasRustup) {
    $targets = rustup target list --installed 2>$null
    $hasMsvcTarget = $targets -match "x86_64-pc-windows-msvc"
    Write-Status "Rust target MSVC x64" $hasMsvcTarget
    if (-not $hasMsvcTarget) {
        Write-Host "  Configuration..." -ForegroundColor Yellow
        rustup default stable-x86_64-pc-windows-msvc
        rustup target add x86_64-pc-windows-msvc
    }
}

# ── 9. cbindgen ──────────────────────────────────────────────────────
$hasCbindgen = Test-Command "cbindgen"
$cbVer = if ($hasCbindgen) { (cbindgen --version 2>$null) } else { "" }
Write-Status "cbindgen" $hasCbindgen $cbVer
if (-not $hasCbindgen) {
    Write-Host "  Installation (cargo install cbindgen)..." -ForegroundColor Yellow
    cargo install cbindgen --version "0.29.2"
}

# ── 10. 7-Zip ────────────────────────────────────────────────────────
# Necessaire pour extraire les sources Qt.
$has7z = (Test-Command "7z") -or `
         (Test-Path "${env:ProgramFiles}\7-Zip\7z.exe") -or `
         (Test-Path "${env:ProgramFiles(x86)}\7-Zip\7z.exe")
Write-Status "7-Zip" $has7z
if (-not $has7z) {
    Write-Host "  Installation..." -ForegroundColor Yellow
    winget install -e --id 7zip.7zip --source winget
}

# ── 11. vcpkg ────────────────────────────────────────────────────────
$vcpkgPath = "C:\vcpkg"
$hasVcpkg = Test-Path "$vcpkgPath\vcpkg.exe"
Write-Status "vcpkg" $hasVcpkg $(if ($hasVcpkg) { $vcpkgPath })
if (-not $hasVcpkg) {
    Write-Host "  Installation..." -ForegroundColor Yellow
    git clone https://github.com/microsoft/vcpkg.git $vcpkgPath
    & "$vcpkgPath\bootstrap-vcpkg.bat" -disableMetrics
}

# ── 12. LibArchive (vcpkg, static) ──────────────────────────────────
$hasLibArchive = Test-Path "$vcpkgPath\installed\x64-windows-static\lib\archive.lib"
Write-Status "LibArchive (x64-windows-static)" $hasLibArchive
if (-not $hasLibArchive) {
    Write-Host "  Installation via vcpkg..." -ForegroundColor Yellow
    & "$vcpkgPath\vcpkg.exe" install libarchive:x64-windows-static
}

# ── Resume ───────────────────────────────────────────────────────────
Write-Host ""
Write-Host "=== Verification terminee ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Prochaine etape :" -ForegroundColor White
Write-Host "  Si Qt statique n'est pas encore builde :" -ForegroundColor Gray
Write-Host "    .\02-build-qt-static.ps1" -ForegroundColor Yellow
Write-Host "  Sinon, builder le projet directement :" -ForegroundColor Gray
Write-Host "    .\03-build-rpgmtranslate.ps1" -ForegroundColor Yellow
