#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.SYNOPSIS
    Configure, compile et vérifie rpgmtranslate-qt en Release pour Windows x64.

.DESCRIPTION
    Ce script est le script "build-only" : il suppose que Qt statique,
    Visual Studio, CMake, Rust et cbindgen sont déjà installés (vérifiés
    par 01-check-prerequisites.ps1 et installés par 02-build-qt-static.ps1).

    Étapes réalisées :
      1. Vérification des outils requis (versions minimales).
      2. Résolution automatique de la racine Qt (Qt6Config.cmake).
      3. Résolution automatique de vcpkg.
      4. Installation de libarchive:x64-windows-static via vcpkg si absent.
      5. Téléchargement de rapidhash.h si absent.
      6. Configuration CMake (Visual Studio 17 2022, x64).
      7. Build Release.
      8. Vérification via dumpbin /dependents : aucune Qt*.dll ne doit
         apparaître si Qt a été buildé statiquement.

.PARAMETER QtRoot
    Racine de l'installation Qt (dossier contenant lib\cmake\Qt6).
    Exemple : C:\Qt\static\Qt-6.9.2
    Si absent, le script cherche dans QT_ROOT, Qt6_DIR, C:\Qt\static\*.

.PARAMETER BuildDir
    Répertoire de build CMake (relatif à la racine du dépôt). Défaut : build

.PARAMETER BuildType
    Configuration CMake. Défaut : Release

.PARAMETER VcpkgRoot
    Racine vcpkg. Si absent, cherche dans VCPKG_ROOT,
    VCPKG_INSTALLATION_ROOT, C:\vcpkg, %USERPROFILE%\vcpkg.

.PARAMETER RapidHashDir
    Répertoire contenant rapidhash.h. Défaut : <repo>\deps\rapidhash

.PARAMETER SkipDependencyCheck
    Ne pas exécuter la vérification dumpbin.

.PARAMETER Fresh
    Supprime le répertoire de build avant de reconfigurer.

.EXAMPLE
    .\scripts\03-build-rpgmtranslate.ps1 -QtRoot C:\Qt\static\Qt-6.9.2
    .\scripts\03-build-rpgmtranslate.ps1 -QtRoot C:\Qt\static\Qt-6.9.2 -Fresh
#>
param(
    [string] $QtRoot              = '',
    [string] $BuildDir            = 'build',
    [string] $BuildType           = 'Release',
    [string] $VcpkgRoot           = '',
    [string] $RapidHashDir        = '',
    [switch] $SkipDependencyCheck,
    [switch] $Fresh
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Step([string]$Msg) {
    Write-Host ''
    Write-Host "▶  $Msg" -ForegroundColor Cyan
}

function Fail([string]$Msg) {
    Write-Host "✖  $Msg" -ForegroundColor Red
    exit 1
}

function Require-Tool([string]$Name, [string]$Hint = '') {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        $msg = "'$Name' absent du PATH."
        if ($Hint) { $msg += " $Hint" }
        Fail $msg
    }
}

# Active vcvars64.bat si cl.exe est absent du PATH.
function Ensure-VsEnv {
    if (Get-Command cl -ErrorAction SilentlyContinue) { return }

    $vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (-not (Test-Path $vsWhere)) {
        $vsWhere = "$env:ProgramFiles\Microsoft Visual Studio\Installer\vswhere.exe"
    }
    if (-not (Test-Path $vsWhere)) {
        Fail "cl.exe absent du PATH et vswhere.exe introuvable. Ouvrez un 'x64 Native Tools Command Prompt for VS 2022'."
    }

    $vsPath = & $vsWhere -latest -products * `
        -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null | Select-Object -First 1

    if (-not $vsPath) {
        Fail "Visual Studio 2022 avec Desktop C++ non trouvé."
    }

    $vcvars = "$vsPath\VC\Auxiliary\Build\vcvars64.bat"
    Write-Host "  Activation VS : $vcvars" -ForegroundColor DarkGray
    cmd /c """$vcvars"" && set" 2>$null | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
        }
    }
}

# ── Racine du dépôt ───────────────────────────────────────────────────────────
# PSScriptRoot est <repo>\scripts → le dépôt est un niveau au-dessus.
$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not (Test-Path (Join-Path $repoRoot 'CMakeLists.txt'))) {
    Fail "CMakeLists.txt introuvable dans '$repoRoot'. Lancez ce script depuis <repo>\scripts\ ou <repo>."
}

# ── Bannière ──────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host 'rpgmtranslate-qt — Build local Windows' -ForegroundColor Cyan
Write-Host ('=' * 60) -ForegroundColor Cyan
Write-Host "  Dépôt      : $repoRoot"
Write-Host "  Build dir  : $BuildDir"
Write-Host "  Config     : $BuildType"

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 1 — Vérification des outils
# ════════════════════════════════════════════════════════════════════════════
Write-Step "Vérification des outils"

Ensure-VsEnv

Require-Tool 'cmake'    'Installez CMake >= 3.31 : https://cmake.org/download/'
Require-Tool 'cargo'    'Installez Rust depuis https://rustup.rs/'
Require-Tool 'cbindgen' 'Installez : cargo install cbindgen --version 0.29.2'

# CMake >= 3.31
$cmakeVerStr = (cmake --version 2>&1 | Select-Object -First 1) -replace 'cmake version ', ''
$cmakeVer    = [version]$cmakeVerStr.Trim()
if ($cmakeVer -lt [version]'3.31.0') {
    Fail "CMake $cmakeVer trouvé mais >= 3.31.0 requis. Mettez CMake à jour."
}
Write-Host "  CMake    : v$cmakeVer   ✔" -ForegroundColor Green

# Rust >= 1.87 (Cargo.toml edition = "2024")
$rustVerStr = (rustc --version 2>&1) -replace 'rustc ', '' -replace ' .*', ''
$rustVer    = [version]$rustVerStr.Trim()
if ($rustVer -lt [version]'1.87.0') {
    Fail "Rust $rustVer trouvé mais >= 1.87.0 requis (edition 2024). Lancez : rustup update stable"
}
Write-Host "  Rust     : v$rustVer   ✔" -ForegroundColor Green

# cbindgen >= 0.29.2
$cbVer = [version]((cbindgen --version 2>&1) -replace 'cbindgen ', '').Trim()
if ($cbVer -lt [version]'0.29.2') {
    Fail "cbindgen $cbVer trouvé mais >= 0.29.2 requis. Lancez : cargo install cbindgen --version 0.29.2"
}
Write-Host "  cbindgen : v$cbVer   ✔" -ForegroundColor Green

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 2 — Résolution de Qt
# ════════════════════════════════════════════════════════════════════════════
Write-Step "Résolution de l'installation Qt"

if (-not $QtRoot) {
    # Recherche dans les emplacements courants
    $qtCandidates = @(
        $env:QT_ROOT,
        $env:Qt6_DIR
    )
    # Ajouter les sous-dossiers Qt6_DIR/../../../ (lib/cmake/Qt6 → root)
    if ($env:Qt6_DIR) {
        $qtCandidates += [System.IO.Path]::GetFullPath((Join-Path $env:Qt6_DIR '..\..\..\..'))
    }
    $qtCandidates += @(
        'C:\Qt\static',
        "$env:USERPROFILE\Qt"
    )

    foreach ($c in $qtCandidates) {
        if (-not $c) { continue }
        if (-not (Test-Path $c)) { continue }

        # Cas 1 : c est directement la racine Qt (contient lib\cmake\Qt6)
        if (Test-Path (Join-Path $c 'lib\cmake\Qt6\Qt6Config.cmake')) {
            $QtRoot = $c; break
        }

        # Cas 2 : c est un répertoire parent (ex. C:\Qt\static contient Qt-6.9.2\)
        $found = Get-ChildItem $c -Filter 'Qt6Config.cmake' -Recurse -Depth 6 -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($found) {
            # Structure attendue : <QtRoot>\lib\cmake\Qt6\Qt6Config.cmake
            # $found.DirectoryName pointe sur Qt6\ → remonter 3 niveaux.
            $QtRoot = [System.IO.Path]::GetFullPath(
                (Join-Path $found.DirectoryName '..\..\..'))
            break
        }
    }
}

if (-not $QtRoot) {
    Fail "Racine Qt introuvable. Passez -QtRoot ou lancez 02-build-qt-static.ps1 d'abord."
}

$qt6ConfigFile = Join-Path $QtRoot 'lib\cmake\Qt6\Qt6Config.cmake'
if (-not (Test-Path $qt6ConfigFile)) {
    Fail "Qt6Config.cmake introuvable sous '$QtRoot'. Vérifiez -QtRoot."
}
Write-Host "  Qt root  : $QtRoot" -ForegroundColor Green

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 3 — Résolution de vcpkg
# ════════════════════════════════════════════════════════════════════════════
Write-Step "Résolution de vcpkg"

if (-not $VcpkgRoot) {
    foreach ($c in @(
        $env:VCPKG_ROOT,
        $env:VCPKG_INSTALLATION_ROOT,
        'C:\vcpkg',
        "$env:USERPROFILE\vcpkg"
    )) {
        if ($c -and (Test-Path "$c\vcpkg.exe")) { $VcpkgRoot = $c; break }
    }
}

if (-not $VcpkgRoot -or -not (Test-Path "$VcpkgRoot\vcpkg.exe")) {
    Fail "vcpkg introuvable. Définissez VCPKG_ROOT ou passez -VcpkgRoot. Voir https://github.com/microsoft/vcpkg"
}
Write-Host "  vcpkg    : $VcpkgRoot" -ForegroundColor Green

# Installation de libarchive:x64-windows-static (triplet /MT, cohérent avec
# CMAKE_MSVC_RUNTIME_LIBRARY = "MultiThreaded" dans CMakeLists.txt)
$installed = & "$VcpkgRoot\vcpkg.exe" list 2>&1 | Where-Object { $_ -match 'libarchive:x64-windows-static' }
if ($installed) {
    Write-Host "  libarchive:x64-windows-static déjà installé." -ForegroundColor DarkGray
} else {
    Write-Host "  Installation libarchive:x64-windows-static via vcpkg…" -ForegroundColor DarkGray
    & "$VcpkgRoot\vcpkg.exe" install 'libarchive:x64-windows-static'
    if ($LASTEXITCODE -ne 0) { Fail "vcpkg install libarchive a échoué." }
    Write-Host "  ✔ libarchive installé." -ForegroundColor Green
}

$vcpkgToolchain = Join-Path $VcpkgRoot 'scripts\buildsystems\vcpkg.cmake'

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 4 — rapidhash (header unique)
# ════════════════════════════════════════════════════════════════════════════
Write-Step "Vérification de rapidhash.h"

if (-not $RapidHashDir) {
    $RapidHashDir = Join-Path $repoRoot 'deps\rapidhash'
}

$rapidHashFile = Join-Path $RapidHashDir 'rapidhash.h'
if (Test-Path $rapidHashFile) {
    Write-Host "  rapidhash.h trouvé : $RapidHashDir" -ForegroundColor DarkGray
} else {
    New-Item -ItemType Directory -Force -Path $RapidHashDir | Out-Null
    Write-Host "  Téléchargement de rapidhash.h…" -ForegroundColor DarkGray
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest `
        -Uri 'https://raw.githubusercontent.com/Nicoshev/rapidhash/master/rapidhash.h' `
        -OutFile $rapidHashFile
    Write-Host "  ✔ rapidhash.h téléchargé dans $RapidHashDir" -ForegroundColor Green
}

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 5 — Configure CMake
# ════════════════════════════════════════════════════════════════════════════
Write-Step "Configuration CMake (Visual Studio 17 2022 · x64)"

$buildPath = Join-Path $repoRoot $BuildDir

if ($Fresh -and (Test-Path $buildPath)) {
    Write-Host "  --fresh : suppression de $buildPath" -ForegroundColor DarkGray
    Remove-Item $buildPath -Recurse -Force
}

$cmakeArgs = @(
    '-S', $repoRoot,
    '-B', $buildPath,
    '-G', 'Visual Studio 17 2022',
    '-A', 'x64',
    "-DCMAKE_TOOLCHAIN_FILE=$vcpkgToolchain",
    '-DVCPKG_TARGET_TRIPLET=x64-windows-static',
    "-DCMAKE_PREFIX_PATH=$QtRoot",
    "-DRAPIDHASH_INCLUDE_DIRS=$RapidHashDir"
)

Write-Host "  cmake $($cmakeArgs -join ' ')" -ForegroundColor DarkGray
cmake @cmakeArgs
if ($LASTEXITCODE -ne 0) { Fail "cmake configure a échoué (code $LASTEXITCODE)." }
Write-Host "  ✔ Configure réussi." -ForegroundColor Green

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 6 — Build
# ════════════════════════════════════════════════════════════════════════════
Write-Step "Build $BuildType"

cmake --build $buildPath --config $BuildType --parallel
if ($LASTEXITCODE -ne 0) { Fail "cmake --build a échoué (code $LASTEXITCODE)." }
Write-Host "  ✔ Build réussi." -ForegroundColor Green

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 7 — Localisation de l'exécutable
# ════════════════════════════════════════════════════════════════════════════
Write-Step "Localisation de l'exécutable"

# CMakeLists.txt : CMAKE_RUNTIME_OUTPUT_DIRECTORY = target/bin
# Le générateur VS ajoute le sous-dossier de config → target\bin\Release
$exePath = Join-Path $buildPath "target\bin\$BuildType\rpgmtranslate.exe"
if (-not (Test-Path $exePath)) {
    # Générateur à config unique (ex. Ninja) : pas de sous-dossier
    $exePath = Join-Path $buildPath 'target\bin\rpgmtranslate.exe'
}
if (-not (Test-Path $exePath)) {
    Fail "Exécutable introuvable. Chemins essayés :`n  $buildPath\target\bin\$BuildType\rpgmtranslate.exe`n  $buildPath\target\bin\rpgmtranslate.exe"
}
Write-Host "  Exécutable : $exePath" -ForegroundColor Green

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 8 — Vérification des dépendances (dumpbin)
# ════════════════════════════════════════════════════════════════════════════
if (-not $SkipDependencyCheck) {
    Write-Step "Vérification des dépendances (dumpbin /dependents)"

    $dumpbin = Get-Command 'dumpbin' -ErrorAction SilentlyContinue
    if (-not $dumpbin) {
        Write-Host "  [skip] dumpbin absent du PATH (lancez depuis l'environnement VS Developer)." -ForegroundColor DarkGray
    } else {
        $depsOutput = (dumpbin /dependents $exePath 2>&1) -join "`n"

        # DLL Qt : Qt6*.dll / Qt5*.dll
        $qtDlls = [regex]::Matches($depsOutput, 'Qt\d\w+\.dll') |
            ForEach-Object { $_.Value } | Sort-Object -Unique

        if ($qtDlls.Count -gt 0) {
            Write-Host "  ⚠  Dépendances Qt DLL détectées (build dynamique) :" -ForegroundColor Yellow
            $qtDlls | ForEach-Object { Write-Host "     $_" -ForegroundColor Yellow }
            Write-Host "  → Pour un .exe sans DLL, compilez Qt statiquement avec 02-build-qt-static.ps1." -ForegroundColor DarkGray
        } else {
            Write-Host "  ✔ Aucune Qt DLL détectée — build 100 % statique." -ForegroundColor Green
        }

        # Toutes les DLL importées non-système (information)
        $sysPatterns = @('KERNEL32','USER32','GDI32','ADVAPI32','SHELL32','OLE32','OLEAUT32',
                         'NTDLL','MSVCRT','WS2_32','CRYPT32','BCRYPT','SECUR32','USERENV',
                         'WINMM','WINSPOOL','COMDLG32','SHLWAPI','COMCTL32','RPCRT4',
                         'MSVCP','VCRUNTIME','UCRTBASE','API-MS-WIN')
        $allDlls = [regex]::Matches($depsOutput, '[\w\-]+\.dll') |
            ForEach-Object { $_.Value.ToUpper() } |
            Where-Object {
                $d = $_
                -not ($sysPatterns | Where-Object { $d.StartsWith($_) })
            } | Sort-Object -Unique
        if ($allDlls) {
            Write-Host "  DLL non-système importées :" -ForegroundColor DarkGray
            $allDlls | ForEach-Object { Write-Host "    $_" -ForegroundColor DarkGray }
        }
    }
}

# ── Résumé ────────────────────────────────────────────────────────────────────
Write-Host ''
Write-Host ('=' * 60) -ForegroundColor Green
Write-Host "✔  Build terminé." -ForegroundColor Green
Write-Host "   $exePath" -ForegroundColor Green
Write-Host ''
