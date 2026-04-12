#!/usr/bin/env pwsh
# 01-check-prerequisites.ps1
# Validate the toolchain required by 02/03 scripts.

$ErrorActionPreference = "Stop"

function Test-Tool {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Command
    )

    $cmd = Get-Command $Command -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        Write-Host "[OK]    $Name -> $($cmd.Source)" -ForegroundColor Green
        return $true
    }

    Write-Host "[MISSING] $Name ($Command)" -ForegroundColor Red
    return $false
}

function Get-CMakeVersion {
    try {
        $line = (cmake --version 2>$null | Select-Object -First 1)
        if ($line -match "cmake version (\d+\.\d+\.\d+)") {
            return $Matches[1]
        }
    } catch {}

    return $null
}

Write-Host "Checking prerequisites for rpgmtranslate-qt custom build scripts..." -ForegroundColor Cyan
Write-Host ""

$allOk = $true

if (-not $env:VSINSTALLDIR) {
    Write-Host "[WARN] Not running inside Developer PowerShell / x64 Native Tools shell." -ForegroundColor Yellow
    Write-Host "       02/03 scripts should be run from an MSVC x64 shell." -ForegroundColor Yellow
}

$allOk = (Test-Tool -Name "MSVC compiler" -Command "cl") -and $allOk
$allOk = (Test-Tool -Name "LLVM clang-cl" -Command "clang-cl") -and $allOk
$allOk = (Test-Tool -Name "CMake" -Command "cmake") -and $allOk
$allOk = (Test-Tool -Name "Ninja" -Command "ninja") -and $allOk
$allOk = (Test-Tool -Name "Git" -Command "git") -and $allOk
$allOk = (Test-Tool -Name "Python" -Command "python") -and $allOk
$allOk = (Test-Tool -Name "Rust compiler" -Command "rustc") -and $allOk
$allOk = (Test-Tool -Name "Cargo" -Command "cargo") -and $allOk
$allOk = (Test-Tool -Name "cbindgen" -Command "cbindgen") -and $allOk
$allOk = (Test-Tool -Name "7-Zip" -Command "7z") -and $allOk

$cmakeVersion = Get-CMakeVersion
if ($null -ne $cmakeVersion) {
    Write-Host "[INFO] CMake version: $cmakeVersion" -ForegroundColor Gray
}

$vcpkgRoot = $null
if ($env:VCPKG_ROOT -and (Test-Path "$($env:VCPKG_ROOT)\vcpkg.exe")) {
    $vcpkgRoot = $env:VCPKG_ROOT
} elseif (Test-Path "C:\vcpkg\vcpkg.exe") {
    $vcpkgRoot = "C:\vcpkg"
} elseif (Test-Path "F:\vcpkg\vcpkg.exe") {
    $vcpkgRoot = "F:\vcpkg"
}

if ($null -ne $vcpkgRoot) {
    Write-Host "[OK]    vcpkg -> $vcpkgRoot" -ForegroundColor Green
} else {
    Write-Host "[MISSING] vcpkg (set VCPKG_ROOT or install in C:\vcpkg / F:\vcpkg)" -ForegroundColor Red
    $allOk = $false
}

Write-Host ""
if ($allOk) {
    Write-Host "All required prerequisites are available." -ForegroundColor Green
    Write-Host "Next: run ./02-build-qt-static.ps1 (once), then ./03-build-rpgmtranslate.ps1." -ForegroundColor Cyan
    exit 0
}

Write-Host "Some prerequisites are missing. Fix them, then rerun this script." -ForegroundColor Red
exit 1