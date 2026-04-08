#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.SYNOPSIS
    Verifies all prerequisites for building rpgmtranslate-qt on Windows.

.DESCRIPTION
    Checks for: Visual Studio 2022 (MSVC C++ workload), CMake (>=3.31),
    Ninja, Git, Rust (>=1.87), cbindgen (>=0.29.2), vcpkg, 7-Zip.
    Reports version + path for every tool. Exits with code 1 if any
    REQUIRED tool is missing or below the required version.

.PARAMETER Fix
    Attempt to install missing tools automatically via winget / cargo
    where possible. Only tools that can be installed without interactive
    prompts are handled; others print a download URL.

.EXAMPLE
    .\01-check-prerequisites.ps1
    .\01-check-prerequisites.ps1 -Fix
#>
param(
    [switch]$Fix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helpers ──────────────────────────────────────────────────────────────────

$script:allOk = $true

enum CheckStatus { OK; WARN; FAIL }

function Write-Status {
    param(
        [CheckStatus]$Status,
        [string]$Label,
        [string]$Detail = ''
    )
    $color = switch ($Status) {
        'OK'   { 'Green'  }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red'    }
    }
    $icon = switch ($Status) {
        'OK'   { '[OK]  ' }
        'WARN' { '[WARN]' }
        'FAIL' { '[FAIL]' }
    }
    Write-Host ("{0} {1,-35} {2}" -f $icon, $Label, $Detail) -ForegroundColor $color
    if ($Status -eq [CheckStatus]::FAIL) { $script:allOk = $false }
}

function Get-CommandPath {
    param([string]$Name)
    try { (Get-Command $Name -ErrorAction Stop).Source } catch { $null }
}

function Parse-SemVer {
    param([string]$Text)
    if ($Text -match '(\d+)\.(\d+)\.(\d+)') {
        return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
    }
    if ($Text -match '(\d+)\.(\d+)') {
        return [version]"$($Matches[1]).$($Matches[2]).0"
    }
    return $null
}

function Compare-Min {
    param([version]$Got, [version]$Min)
    $Got -ge $Min
}

# ── Title ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "rpgmtranslate-qt – Prerequisites Check" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host ""

# ────────────────────────────────────────────────────────────────────────────
# 1. Visual Studio 2022 / MSVC Build Tools (C++ Desktop workload)
# ────────────────────────────────────────────────────────────────────────────
Write-Host "── Compiler ──────────────────────────────────────────────" -ForegroundColor DarkGray

$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vsWhere)) {
    $vsWhere = "$env:ProgramFiles\Microsoft Visual Studio\Installer\vswhere.exe"
}

$vsFound     = $false
$vsVersion   = $null
$msvcPath    = $null
$clPath      = $null

if (Test-Path $vsWhere) {
    $vsInfo = & $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
        -property installationPath 2>$null
    if ($vsInfo) {
        $vsFound   = $true
        $vsVersion = (& $vsWhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 `
            -property catalog_productDisplayVersion 2>$null)
        # Find cl.exe
        $clCandidates = Get-ChildItem "$vsInfo\VC\Tools\MSVC\*\bin\Hostx64\x64\cl.exe" -ErrorAction SilentlyContinue
        if ($clCandidates) {
            $clPath = ($clCandidates | Sort-Object FullName -Descending | Select-Object -First 1).FullName
            $msvcPath = Split-Path (Split-Path $clPath -Parent) -Parent | Split-Path -Parent | Split-Path -Parent
        }
    }
}

if (-not $vsFound) {
    # Maybe already on PATH (e.g. Developer PowerShell)
    $clPath = Get-CommandPath 'cl'
}

if ($vsFound -or $clPath) {
    $detail = if ($vsVersion) { "VS $vsVersion" } elseif ($clPath) { $clPath } else { "(on PATH)" }
    Write-Status OK "Visual Studio 2022 (MSVC)" $detail
} else {
    Write-Status FAIL "Visual Studio 2022 (MSVC)" "Not found. Install from https://visualstudio.microsoft.com/downloads/ (Desktop C++ workload)"
    if ($Fix) {
        Write-Host "  → Attempting install via winget..." -ForegroundColor DarkYellow
        winget install --id Microsoft.VisualStudio.2022.BuildTools --override "--add Microsoft.VisualStudio.Workload.VCTools --includeRecommended --passive" 2>&1 | Out-Null
    }
}

# Check that cl.exe is accessible from an x64 Native Tools environment
$clOnPath = Get-CommandPath 'cl'
if ($clOnPath) {
    Write-Status OK "cl.exe on PATH" $clOnPath
} else {
    Write-Status WARN "cl.exe not on PATH" "Launch from 'x64 Native Tools Command Prompt for VS 2022'"
}

# ────────────────────────────────────────────────────────────────────────────
# 2. CMake (>= 3.31)
# ────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "── Build tools ───────────────────────────────────────────" -ForegroundColor DarkGray

$cmakeMin = [version]'3.31.0'
$cmakePath = Get-CommandPath 'cmake'
if ($cmakePath) {
    $cmakeRaw = (cmake --version 2>&1 | Select-Object -First 1)
    $cmakeVer = Parse-SemVer $cmakeRaw
    if ($cmakeVer -and (Compare-Min $cmakeVer $cmakeMin)) {
        Write-Status OK "CMake" "v$cmakeVer  [$cmakePath]"
    } else {
        Write-Status FAIL "CMake" "Found v$cmakeVer but need >=$cmakeMin  [$cmakePath]"
        if ($Fix) {
            Write-Host "  → Attempting install via winget..." -ForegroundColor DarkYellow
            winget install --id Kitware.CMake --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
        }
    }
} else {
    Write-Status FAIL "CMake" "Not found. Get >= $cmakeMin from https://cmake.org/download/"
    if ($Fix) {
        winget install --id Kitware.CMake --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    }
}

# ── Ninja ────────────────────────────────────────────────────────────────────
$ninjaPath = Get-CommandPath 'ninja'
if ($ninjaPath) {
    $ninjaVer = (ninja --version 2>&1)
    Write-Status OK "Ninja" "v$ninjaVer  [$ninjaPath]"
} else {
    Write-Status WARN "Ninja" "Not found (required for Qt static build). Install via 'winget install Ninja-build.Ninja'"
    if ($Fix) {
        winget install --id Ninja-build.Ninja --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    }
}

# ── Git ──────────────────────────────────────────────────────────────────────
$gitPath = Get-CommandPath 'git'
if ($gitPath) {
    $gitVer = (git --version 2>&1) -replace 'git version ', ''
    Write-Status OK "Git" "v$gitVer  [$gitPath]"
} else {
    Write-Status FAIL "Git" "Not found. Install from https://git-scm.com/"
    if ($Fix) {
        winget install --id Git.Git --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    }
}

# ── 7-Zip ────────────────────────────────────────────────────────────────────
$7zPath = Get-CommandPath '7z'
if (-not $7zPath) {
    $7zPath = Get-Item 'C:\Program Files\7-Zip\7z.exe' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
}
if ($7zPath) {
    $7zVer = (& $7zPath i 2>&1 | Select-String '7-Zip' | Select-Object -First 1).ToString().Trim()
    Write-Status OK "7-Zip" "$7zVer  [$7zPath]"
} else {
    Write-Status WARN "7-Zip" "Not found (required for packaging). Install from https://www.7-zip.org/"
    if ($Fix) {
        winget install --id 7zip.7zip --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    }
}

# ────────────────────────────────────────────────────────────────────────────
# 3. Rust toolchain (>= 1.87 for edition 2024)
# ────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "── Rust ──────────────────────────────────────────────────" -ForegroundColor DarkGray

$rustMin = [version]'1.87.0'
$rustupPath = Get-CommandPath 'rustup'
$cargoPath  = Get-CommandPath 'cargo'
$rustcPath  = Get-CommandPath 'rustc'

if ($rustcPath) {
    $rustcRaw = (rustc --version 2>&1)
    $rustVer  = Parse-SemVer $rustcRaw
    if ($rustVer -and (Compare-Min $rustVer $rustMin)) {
        Write-Status OK "Rust (rustc)" "v$rustVer  [$rustcPath]"
    } else {
        Write-Status FAIL "Rust (rustc)" "Found v$rustVer but need >=$rustMin. Run: rustup update stable"
    }
} else {
    Write-Status FAIL "Rust (rustc)" "Not found. Install rustup from https://rustup.rs/"
    if ($Fix) {
        Write-Host "  → Downloading and running rustup-init.exe..." -ForegroundColor DarkYellow
        $rustupInit = "$env:TEMP\rustup-init.exe"
        Invoke-WebRequest -Uri 'https://win.rustup.rs/x86_64' -OutFile $rustupInit
        & $rustupInit -y --default-toolchain stable --default-host x86_64-pc-windows-msvc 2>&1
        Remove-Item $rustupInit -Force
    }
}

if ($cargoPath) {
    Write-Status OK "Cargo" "[$cargoPath]"
} else {
    Write-Status FAIL "Cargo" "Not found (should come with Rust installation)"
}

if ($rustupPath) {
    $rustupVer = (rustup --version 2>&1) -replace 'rustup ', ''
    Write-Status OK "rustup" "v$rustupVer  [$rustupPath]"

    # Verify msvc host is active (required for MSVC builds)
    $activeToolchain = (rustup toolchain list 2>&1 | Where-Object { $_ -match '\(default\)' } | Select-Object -First 1)
    if ($activeToolchain -match 'msvc') {
        Write-Status OK "Rust host (msvc)" $activeToolchain
    } else {
        Write-Status WARN "Rust host (msvc)" "Active: '$activeToolchain'. For MSVC builds, run: rustup default stable-x86_64-pc-windows-msvc"
    }
} else {
    Write-Status WARN "rustup" "Not found (needed to manage Rust versions)"
}

# ── cbindgen (>= 0.29.2) ─────────────────────────────────────────────────────
$cbindgenMin  = [version]'0.29.2'
$cbindgenPath = Get-CommandPath 'cbindgen'
if ($cbindgenPath) {
    $cbindgenVer = Parse-SemVer (cbindgen --version 2>&1)
    if ($cbindgenVer -and (Compare-Min $cbindgenVer $cbindgenMin)) {
        Write-Status OK "cbindgen" "v$cbindgenVer  [$cbindgenPath]"
    } else {
        Write-Status FAIL "cbindgen" "Found v$cbindgenVer but need >=$cbindgenMin. Run: cargo install cbindgen --version 0.29.2"
        if ($Fix -and $cargoPath) { cargo install cbindgen --version '0.29.2' }
    }
} else {
    Write-Status FAIL "cbindgen" "Not found. Run: cargo install cbindgen --version 0.29.2"
    if ($Fix -and $cargoPath) { cargo install cbindgen --version '0.29.2' }
}

# ────────────────────────────────────────────────────────────────────────────
# 4. vcpkg (for LibArchive)
# ────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "── vcpkg / dependencies ──────────────────────────────────" -ForegroundColor DarkGray

$vcpkgPath = $null
# Common locations
$candidates = @(
    $env:VCPKG_ROOT,
    $env:VCPKG_INSTALLATION_ROOT,
    'C:\vcpkg',
    "$env:USERPROFILE\vcpkg",
    "$env:PROGRAMFILES\vcpkg"
)
foreach ($c in $candidates) {
    if ($c -and (Test-Path "$c\vcpkg.exe")) { $vcpkgPath = "$c\vcpkg.exe"; break }
}
if (-not $vcpkgPath) {
    $vcpkgPath = Get-CommandPath 'vcpkg'
}

if ($vcpkgPath) {
    $vcpkgVer = (& $vcpkgPath version 2>&1 | Select-Object -First 1)
    Write-Status OK "vcpkg" "$vcpkgVer  [$vcpkgPath]"

    # Check if libarchive is already installed
    $libArchiveInstalled = (& $vcpkgPath list 2>&1 | Where-Object { $_ -match 'libarchive:x64-windows-static' })
    if ($libArchiveInstalled) {
        Write-Status OK "LibArchive (x64-windows-static)" "already installed"
    } else {
        Write-Status WARN "LibArchive (x64-windows-static)" "Not installed. Run: vcpkg install libarchive:x64-windows-static"
    }
} else {
    Write-Status WARN "vcpkg" "Not found. Install from https://github.com/microsoft/vcpkg or set VCPKG_ROOT. Needed for LibArchive."
}

# ────────────────────────────────────────────────────────────────────────────
# 5. Qt 6 (optional check – may be installed by 02-build-qt-static.ps1)
# ────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "── Qt 6 ──────────────────────────────────────────────────" -ForegroundColor DarkGray

$qtPaths = @(
    $env:Qt6_DIR,
    $env:QT_ROOT,
    'C:\Qt\static',
    'C:\Qt\6*',
    "$env:USERPROFILE\Qt"
)
$qtFound = $false
foreach ($p in $qtPaths) {
    if (-not $p) { continue }
    $expanded = Get-Item $p -ErrorAction SilentlyContinue
    foreach ($e in @($expanded)) {
        $qt6Config = Get-ChildItem "$($e.FullName)" -Recurse -Filter "Qt6Config.cmake" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($qt6Config) {
            $qtFound = $true
            Write-Status OK "Qt 6" "Found at $($e.FullName)"
            break
        }
    }
    if ($qtFound) { break }
}
if (-not $qtFound) {
    Write-Status WARN "Qt 6" "Not found in common locations. Run 02-build-qt-static.ps1 or set Qt6_DIR / QT_ROOT."
}

# ────────────────────────────────────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Cyan
if ($script:allOk) {
    Write-Host "All required prerequisites are satisfied. Ready to build." -ForegroundColor Green
} else {
    Write-Host "One or more required prerequisites are missing. See [FAIL] items above." -ForegroundColor Red
    Write-Host "Re-run with -Fix to attempt automatic installation." -ForegroundColor Yellow
    exit 1
}
Write-Host ""
