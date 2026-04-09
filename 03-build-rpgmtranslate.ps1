#!/usr/bin/env pwsh
# 03-build-rpgmtranslate.ps1
# Build rpgmtranslate-qt avec clang-cl + Qt statique.
# Setup identique au developpeur upstream.
# A executer dans "Developer PowerShell for VS 2022/2026".
# Relancable a chaque modification du code.

param(
    [string]$RepoDir    = "F:\Desktop\rpgmtranslate-qt",
    [string]$QtInstall  = "F:\dev\qt-6.11.0-static-msvc",
    [string]$VcpkgRoot  = "C:\vcpkg",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

# ── Verifier le shell MSVC ───────────────────────────────────────────
if (-not $env:VSINSTALLDIR) {
    Write-Host "ERREUR: Lance ce script depuis 'Developer PowerShell for VS'." -ForegroundColor Red
    exit 1
}

if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    Write-Host "ERREUR: cl.exe introuvable." -ForegroundColor Red
    exit 1
}

# ── Verifier que cl.exe est en mode x64 ─────────────────────────────
$clOutput = (cl 2>&1 | Out-String)
if ($clOutput -notmatch "x64|amd64") {
    Write-Host "ERREUR: cl.exe est en mode x86. Il faut un shell MSVC x64." -ForegroundColor Red
    Write-Host "  Utilise 'x64 Native Tools Command Prompt for VS 2026' puis tape 'pwsh'." -ForegroundColor Yellow
    exit 1
}

# ── Verifier clang-cl ────────────────────────────────────────────────
if (-not (Get-Command clang-cl -ErrorAction SilentlyContinue)) {
    if (Test-Path "${env:ProgramFiles}\LLVM\bin\clang-cl.exe") {
        $env:Path = "${env:ProgramFiles}\LLVM\bin;$env:Path"
    } elseif (Test-Path "${env:ProgramFiles(x86)}\LLVM\bin\clang-cl.exe") {
        $env:Path = "${env:ProgramFiles(x86)}\LLVM\bin;$env:Path"
    } else {
        Write-Host "ERREUR: clang-cl introuvable. Installe LLVM (.\01-check-prerequisites.ps1)" -ForegroundColor Red
        exit 1
    }
}
Write-Host "Compilateur: $(clang-cl --version | Select-Object -First 1)" -ForegroundColor Gray

# ── Verifier Qt statique ────────────────────────────────────────────
if (-not (Test-Path "$QtInstall\bin\qmake.exe")) {
    Write-Host "ERREUR: Qt statique introuvable dans $QtInstall" -ForegroundColor Red
    Write-Host "Lance d'abord: .\02-build-qt-static.ps1" -ForegroundColor Yellow
    exit 1
}

# ── Verifier le repo ────────────────────────────────────────────────
if (-not (Test-Path "$RepoDir\CMakeLists.txt")) {
    Write-Host "ERREUR: CMakeLists.txt introuvable dans $RepoDir" -ForegroundColor Red
    exit 1
}

Set-Location $RepoDir

# ── Clean si demande ────────────────────────────────────────────────
if ($Clean -and (Test-Path "build")) {
    Write-Host "Nettoyage du build precedent..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force build
}

# ── Preparer les dependances header-only ────────────────────────────
if (-not (Test-Path "deps\rapidhash\rapidhash.h")) {
    Write-Host "Telechargement de rapidhash.h..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path "deps\rapidhash" | Out-Null
    Invoke-WebRequest `
        -Uri "https://raw.githubusercontent.com/Nicoshev/rapidhash/master/rapidhash.h" `
        -OutFile "deps\rapidhash\rapidhash.h"
}

if (-not (Test-Path "deps\magic_enum\magic_enum.hpp")) {
    Write-Host "Telechargement de magic_enum.hpp..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Force -Path "deps\magic_enum" | Out-Null
    Invoke-WebRequest `
        -Uri "https://raw.githubusercontent.com/Neargye/magic_enum/master/include/magic_enum/magic_enum.hpp" `
        -OutFile "deps\magic_enum\magic_enum.hpp"
}

# ── Configurer avec configure.ps1 du repo ───────────────────────────
Write-Host ""
Write-Host "Configuration CMake (clang-cl + MSVC linker)..." -ForegroundColor Cyan

# On utilise clang-cl comme le developpeur upstream.
# configure.ps1 est le script du repo, on ne le modifie pas.
pwsh .\configure.ps1 `
    --fresh `
    -G=Ninja `
    --cc=clang-cl `
    --cxx=clang-cl `
    "CMAKE_BUILD_TYPE=Release" `
    "RAPIDHASH_INCLUDE_DIRS=$RepoDir/deps/rapidhash" `
    "CMAKE_PREFIX_PATH=$QtInstall" `
    "CMAKE_TOOLCHAIN_FILE=$VcpkgRoot/scripts/buildsystems/vcpkg.cmake" `
    "VCPKG_TARGET_TRIPLET=x64-windows-static" `
    "CMAKE_CXX_FLAGS=-I$RepoDir/deps"

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERREUR: cmake configure a echoue." -ForegroundColor Red
    exit 1
}

# ── Build ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Build..." -ForegroundColor Cyan

cmake --build build --config Release --parallel

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERREUR: Le build a echoue." -ForegroundColor Red
    exit 1
}

# ── Verification ─────────────────────────────────────────────────────
$exe = "build\target\bin\rpgmtranslate.exe"

if (-not (Test-Path $exe)) {
    Write-Host "ERREUR: $exe introuvable." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Build reussi !" -ForegroundColor Green
Write-Host "  Binaire: $RepoDir\$exe" -ForegroundColor White

# Verifier le linkage statique
Write-Host ""
Write-Host "Verification des dependances DLL:" -ForegroundColor Cyan
$dumpbin = & dumpbin /dependents $exe 2>$null
$qtDeps = $dumpbin | Select-String "Qt6"
if ($qtDeps) {
    Write-Host "  ATTENTION: Le binaire depend encore de DLLs Qt :" -ForegroundColor Yellow
    $qtDeps | ForEach-Object { Write-Host "    $_" -ForegroundColor Yellow }
} else {
    Write-Host "  Aucune dependance Qt DLL - linkage statique OK" -ForegroundColor Green
}

$size = [math]::Round((Get-Item $exe).Length / 1MB, 1)
Write-Host ""
Write-Host "Taille: ${size} Mo" -ForegroundColor Gray
Write-Host ""
Write-Host "Pour compresser avec UPX (optionnel):" -ForegroundColor Gray
Write-Host "  upx --best --lzma $exe" -ForegroundColor Yellow
