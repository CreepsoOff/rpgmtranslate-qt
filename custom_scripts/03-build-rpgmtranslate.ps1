#!/usr/bin/env pwsh
# 03-build-rpgmtranslate.ps1
# Configure + build rpgmtranslate-qt using the canonical build flow.

param(
    [string]$RepoDir = "F:\Desktop\rpgmtranslate-qt",
    [string]$QtInstall = "F:\dev\qt-6.11.0-static-msvc",
    [string]$VcpkgRoot = "",
    [ValidateSet("Debug", "Release", "RelWithDebInfo", "MinSizeRel")]
    [string]$BuildType = "RelWithDebInfo",
    [switch]$Clean,
    [int]$Jobs = 0
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Resolve-VcpkgRoot([string]$InputRoot) {
    if ($InputRoot -and (Test-Path "$InputRoot\vcpkg.exe")) {
        return $InputRoot
    }

    if ($env:VCPKG_ROOT -and (Test-Path "$($env:VCPKG_ROOT)\vcpkg.exe")) {
        $isVsBundled = $env:VCPKG_ROOT -match "\\Microsoft Visual Studio\\.+\\VC\\vcpkg$"
        if (-not $isVsBundled) {
            return $env:VCPKG_ROOT
        }
    }

    if (Test-Path "C:\vcpkg\vcpkg.exe") {
        return "C:\vcpkg"
    }

    if (Test-Path "F:\vcpkg\vcpkg.exe") {
        return "F:\vcpkg"
    }

    return ""
}

function Ensure-HeaderDeps([string]$Root) {
    $rapidDir = "$Root\deps\rapidhash"
    $rapidHeader = "$rapidDir\rapidhash.h"
    if (-not (Test-Path $rapidHeader)) {
        New-Item -ItemType Directory -Force -Path $rapidDir | Out-Null
        Invoke-WebRequest `
            -Uri "https://raw.githubusercontent.com/Nicoshev/rapidhash/master/rapidhash.h" `
            -OutFile $rapidHeader
    }

    $magicDir = "$Root\deps\magic_enum\magic_enum"
    $magicHeader = "$magicDir\magic_enum.hpp"
    if (-not (Test-Path $magicHeader)) {
        New-Item -ItemType Directory -Force -Path $magicDir | Out-Null
        Invoke-WebRequest `
            -Uri "https://raw.githubusercontent.com/Neargye/magic_enum/master/include/magic_enum/magic_enum.hpp" `
            -OutFile $magicHeader
    }

}

if (-not $env:VSINSTALLDIR) {
    Fail "Run this script inside Developer PowerShell / x64 Native Tools shell."
}

if (-not (Test-Path "$RepoDir\configure.ps1")) {
    Fail "configure.ps1 not found in repo path: $RepoDir"
}

if (-not (Test-Path "$QtInstall\bin\qmake.exe")) {
    Fail "Qt install is missing qmake.exe: $QtInstall"
}

if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    Fail "cl.exe is not available in PATH."
}

if (-not (Get-Command clang-cl -ErrorAction SilentlyContinue)) {
    $llvmCandidates = @(
        "${env:ProgramFiles}\\LLVM\\bin",
        "${env:ProgramFiles(x86)}\\LLVM\\bin"
    )

    foreach ($candidate in $llvmCandidates) {
        if (Test-Path "$candidate\\clang-cl.exe") {
            $env:Path = "$candidate;$env:Path"
            break
        }
    }
}

if (-not (Get-Command clang-cl -ErrorAction SilentlyContinue)) {
    Fail "clang-cl is not available in PATH."
}

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) {
    Fail "cmake is not available in PATH."
}

$clText = (cl 2>&1 | Out-String)
if ($clText -notmatch "x64|amd64") {
    Fail "cl.exe is not in x64 mode. Open an x64 Native Tools shell first."
}

$resolvedVcpkg = Resolve-VcpkgRoot $VcpkgRoot
if ($resolvedVcpkg -eq "") {
    Fail "vcpkg not found. Set VCPKG_ROOT or pass -VcpkgRoot."
}
Write-Host "Using vcpkg root: $resolvedVcpkg" -ForegroundColor Gray

if ($Jobs -le 0) {
    $Jobs = [Math]::Max(1, [Environment]::ProcessorCount - 1)
}

Set-Location $RepoDir

if ($Clean -and (Test-Path "$RepoDir\build")) {
    Write-Host "Cleaning build directory..." -ForegroundColor Yellow
    try {
        Remove-Item -Recurse -Force "$RepoDir\build" -ErrorAction Stop
    } catch {
        Fail "Failed to clean build directory (likely locked file). Close rpgmtranslate.exe and retry."
    }
}

Ensure-HeaderDeps -Root $RepoDir

if ([string]::IsNullOrWhiteSpace($env:RUSTFLAGS)) {
    $env:RUSTFLAGS = "-Ctarget-feature=+crt-static,+aes,+sse2"
} elseif ($env:RUSTFLAGS -notmatch "crt-static|\\+aes|\\+sse2") {
    $env:RUSTFLAGS =
        "$($env:RUSTFLAGS) -Ctarget-feature=+crt-static,+aes,+sse2"
}

$linker = "link"
$archiver = "lib"

$toolchain = "$resolvedVcpkg\scripts\buildsystems\vcpkg.cmake"

$configureArgs = @(
    "--fresh",
    "-G=Ninja",
    "--cc=clang-cl",
    "--cxx=clang-cl",
    "--ld=$linker",
    "--ar=$archiver",
    "CMAKE_BUILD_TYPE=$BuildType",
    "CMAKE_PREFIX_PATH=$QtInstall",
    "CMAKE_TOOLCHAIN_FILE=$toolchain",
    "VCPKG_TARGET_TRIPLET=x64-windows-static",
    "MSVC_STATIC_RUNTIME=OFF",
    "RAPIDHASH_ROOT=$RepoDir/deps/rapidhash"
)

Write-Host "Configuring project..." -ForegroundColor Cyan
& "$RepoDir\configure.ps1" @configureArgs
if ($LASTEXITCODE -ne 0) {
    Fail "Configure failed."
}

Push-Location "$RepoDir\build"
Write-Host "Building project ($Jobs jobs)..." -ForegroundColor Cyan
cmake --build . --parallel $Jobs
$buildExit = $LASTEXITCODE
Pop-Location

if ($buildExit -ne 0) {
    Fail "Build failed."
}

$exe = "$RepoDir\build\target\bin\rpgmtranslate.exe"
$pdb = "$RepoDir\build\target\bin\rpgmtranslate.pdb"

if (-not (Test-Path $exe)) {
    Fail "Build finished but executable is missing: $exe"
}

Write-Host "Build succeeded." -ForegroundColor Green
Write-Host "Executable: $exe" -ForegroundColor White

if (Test-Path $pdb) {
    Write-Host "PDB:        $pdb" -ForegroundColor White
}
