#!/usr/bin/env pwsh
# 03-build-rpgmtranslate.ps1
# Build rpgmtranslate-qt avec clang-cl + Qt statique.
# Setup identique au developpeur upstream.
# A executer dans "Developer PowerShell for VS 2022/2026".
# Relancable a chaque modification du code.

param(
    [string]$RepoDir    = "F:\Desktop\rpgmtranslate-qt",
    [string]$QtInstall  = "F:\dev\qt-6.11.0-static-msvc",
    [string]$VcpkgRoot  = "",
    [ValidateSet("Debug","Release","RelWithDebInfo","MinSizeRel")]
    [string]$BuildType  = "RelWithDebInfo",
    [switch]$Clean,
    [switch]$CompressUpx,
    [string[]]$UpxArgs = @("--best", "--lzma")
)

$ErrorActionPreference = "Stop"
$RequiredCMakeVersion = [version]"3.31.11"

function Fail([string]$Message) {
    Write-Host "ERREUR: $Message" -ForegroundColor Red
    exit 1
}

function Get-CMakeVersion {
    try {
        $line = (cmake --version 2>$null | Select-Object -First 1)
        if ($line -match "cmake version (\d+)\.(\d+)\.(\d+)") {
            return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
        }
    } catch {}
    return $null
}

# ── Verifier le shell MSVC ───────────────────────────────────────────
if (-not $env:VSINSTALLDIR) {
    Fail "Lance ce script depuis 'Developer PowerShell for VS'."
}

if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    Fail "cl.exe introuvable."
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
        Fail "clang-cl introuvable. Installe LLVM (.\01-check-prerequisites.ps1)."
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
    Fail "CMakeLists.txt introuvable dans $RepoDir."
}

# ── Verifier CMake actif (strict 3.31.11) ───────────────────────────
$cmakeVersion = Get-CMakeVersion
if (-not $cmakeVersion) {
    Write-Host "ERREUR: cmake introuvable dans le PATH." -ForegroundColor Red
    Write-Host "Lance d'abord: .\01-check-prerequisites.ps1" -ForegroundColor Yellow
    exit 1
}

if ($cmakeVersion -ne $RequiredCMakeVersion) {
    Write-Host "ERREUR: CMake $RequiredCMakeVersion requis, detecte: $cmakeVersion" -ForegroundColor Red
    Write-Host "Relance .\01-check-prerequisites.ps1 pour corriger CMake." -ForegroundColor Yellow
    exit 1
}
Write-Host "CMake actif: $(cmake --version | Select-Object -First 1)" -ForegroundColor Gray

# ── Resoudre vcpkg ───────────────────────────────────────────────────
if ($VcpkgRoot) {
    $VcpkgRoot = $VcpkgRoot.Trim('"').Trim("'")
    if (-not (Test-Path "$VcpkgRoot\vcpkg.exe")) {
        Fail "-VcpkgRoot fourni mais vcpkg.exe introuvable dans '$VcpkgRoot'."
    }
} else {
    $candidates = @()

    if ($env:VCPKG_ROOT) {
        $envVcpkg = $env:VCPKG_ROOT.Trim('"').Trim("'")
        $isVsBundled = $envVcpkg -match "\\Microsoft Visual Studio\\.+\\VC\\vcpkg$"
        if ($isVsBundled) {
            Write-Host "VCPKG_ROOT pointe vers le vcpkg embarque de Visual Studio, ignore pour ce build." -ForegroundColor Yellow
        } else {
            $candidates += $envVcpkg
        }
    }

    $candidates += @("C:\vcpkg", "F:\vcpkg")
    $candidates = $candidates | Where-Object { $_ } | Select-Object -Unique

    foreach ($candidate in $candidates) {
        if (Test-Path "$candidate\vcpkg.exe") {
            $VcpkgRoot = $candidate
            break
        }
    }

    if (-not $VcpkgRoot) {
        Write-Host "vcpkg introuvable via VCPKG_ROOT, C:\vcpkg ou F:\vcpkg." -ForegroundColor Yellow
        do {
            $manual = (Read-Host "Chemin vers vcpkg (dossier contenant vcpkg.exe)").Trim('"').Trim("'")
            if (Test-Path "$manual\vcpkg.exe") {
                $VcpkgRoot = $manual
            } else {
                Write-Host "vcpkg.exe introuvable dans '$manual'. Reessaie." -ForegroundColor Red
                $manual = $null
            }
        } while (-not $manual)
    }
}

Set-Location $RepoDir
Write-Host "vcpkg retenu: $VcpkgRoot" -ForegroundColor Gray
Write-Host "BuildType: $BuildType" -ForegroundColor Gray

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

# ── Aligner Rust sur CRT statique (/MT) ─────────────────────────────
$rustTargetFlags = "-Ctarget-feature=+crt-static,+aes,+sse2"
if ($env:RUSTFLAGS -notmatch "\+crt-static") {
    if ([string]::IsNullOrWhiteSpace($env:RUSTFLAGS)) {
        $env:RUSTFLAGS = $rustTargetFlags
    } else {
        $env:RUSTFLAGS = "$($env:RUSTFLAGS) $rustTargetFlags"
    }
}

if ($env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUSTFLAGS -notmatch "\+crt-static") {
    if ([string]::IsNullOrWhiteSpace($env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUSTFLAGS)) {
        $env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUSTFLAGS = $rustTargetFlags
    } else {
        $env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUSTFLAGS = "$($env:CARGO_TARGET_X86_64_PC_WINDOWS_MSVC_RUSTFLAGS) $rustTargetFlags"
    }
}

Write-Host "RUSTFLAGS: $env:RUSTFLAGS" -ForegroundColor Gray

# ── Aligner QT_DISABLE_DEPRECATED_UP_TO avec la build Qt installee ──
$qtDeprecationHeader = Join-Path $QtInstall "include\QtCore\qtdeprecationdefinitions.h"
$qtDeprecationUpTo = $null

if (Test-Path $qtDeprecationHeader) {
    $depMatch = Select-String `
        -Path $qtDeprecationHeader `
        -Pattern '^\s*#\s*define\s+QT_DISABLE_DEPRECATED_UP_TO\s+(0x[0-9A-Fa-f]+)\s*$' `
        | Select-Object -First 1

    if ($depMatch -and $depMatch.Matches.Count -gt 0) {
        $qtDeprecationUpTo = $depMatch.Matches[0].Groups[1].Value.ToLower()
    }
}

$cxxFlags = "-I$RepoDir/deps /EHsc"
if ($qtDeprecationUpTo) {
    Write-Host "QT_DISABLE_DEPRECATED_UP_TO detecte dans Qt: $qtDeprecationUpTo" -ForegroundColor Gray
    $cxxFlags += " -DQT_DISABLE_DEPRECATED_UP_TO=$qtDeprecationUpTo"
} else {
    Write-Host "ATTENTION: impossible de detecter QT_DISABLE_DEPRECATED_UP_TO dans Qt, pas d'override applique." -ForegroundColor Yellow
}

# ── Configurer avec configure.ps1 du repo ───────────────────────────
Write-Host ""
Write-Host "Configuration CMake (clang-cl + MSVC linker)..." -ForegroundColor Cyan

$commonConfigureArgs = @(
    "--fresh",
    "-G=Ninja",
    "--cc=clang-cl",
    "--cxx=clang-cl",
    "--ld=link",
    "CMAKE_BUILD_TYPE=$BuildType",
    "RAPIDHASH_INCLUDE_DIRS=$RepoDir/deps/rapidhash",
    "CMAKE_PREFIX_PATH=$QtInstall",
    "CMAKE_TOOLCHAIN_FILE=$VcpkgRoot/scripts/buildsystems/vcpkg.cmake",
    "VCPKG_TARGET_TRIPLET=x64-windows-static",
    "CMAKE_C23_STANDARD_COMPILE_OPTION=/clang:-std=c23",
    "CMAKE_C23_EXTENSION_COMPILE_OPTION=/clang:-std=c23",
    "CMAKE_C_STANDARD_LATEST=23",
    "CMAKE_TRY_COMPILE_PLATFORM_VARIABLES=CMAKE_C23_STANDARD_COMPILE_OPTION;CMAKE_C23_EXTENSION_COMPILE_OPTION;CMAKE_C_STANDARD_LATEST",
    "CMAKE_CXX_FLAGS=$cxxFlags"
)

# Pour garantir un .pdb en Release/RelWithDebInfo avec clang-cl + link.exe
if ($BuildType -in @("Release", "RelWithDebInfo")) {
    $commonConfigureArgs += @(
        "CMAKE_C_FLAGS_${BuildType}=/Zi",
        "CMAKE_CXX_FLAGS_${BuildType}=/Zi",
        "CMAKE_EXE_LINKER_FLAGS_${BuildType}=/DEBUG"
    )
}

& .\configure.ps1 @commonConfigureArgs

if ($LASTEXITCODE -ne 0) {
    Fail "cmake configure a echoue."
}

# ── Build ────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Build..." -ForegroundColor Cyan

cmake --build build --config $BuildType --parallel

if ($LASTEXITCODE -ne 0) {
    Fail "Le build a echoue."
}

# ── Verification ─────────────────────────────────────────────────────
$exe = "build\target\bin\rpgmtranslate.exe"
$pdb = "build\target\bin\rpgmtranslate.pdb"

if (-not (Test-Path $exe)) {
    Fail "$exe introuvable."
}

Write-Host ""
Write-Host "Build reussi !" -ForegroundColor Green
Write-Host "  Binaire: $RepoDir\$exe" -ForegroundColor White

if (Test-Path $pdb) {
    Write-Host "  PDB:     $RepoDir\$pdb" -ForegroundColor White
} else {
    Write-Host "  PDB:     non trouve a l'emplacement attendu ($RepoDir\$pdb)" -ForegroundColor Yellow
}

if ($CompressUpx) {
    $upx = Get-Command upx -ErrorAction SilentlyContinue
    if (-not $upx) {
        Fail "UPX introuvable dans le PATH. Installe UPX ou lance sans -CompressUpx."
    }

    $backupExe = "$exe.unpacked"
    Copy-Item -LiteralPath $exe -Destination $backupExe -Force

    Write-Host ""
    Write-Host "Compression UPX..." -ForegroundColor Cyan
    & $upx.Source @UpxArgs $exe
    if ($LASTEXITCODE -ne 0) {
        Copy-Item -LiteralPath $backupExe -Destination $exe -Force
        Fail "Compression UPX echouee. EXE restaure depuis $backupExe."
    }

    & $upx.Source -t $exe
    if ($LASTEXITCODE -ne 0) {
        Copy-Item -LiteralPath $backupExe -Destination $exe -Force
        Fail "Test UPX echoue. EXE restaure depuis $backupExe."
    }

    Write-Host "UPX OK. Sauvegarde non compressee: $RepoDir\$backupExe" -ForegroundColor Green
}

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
if (-not $CompressUpx) {
    Write-Host "Pour compresser avec UPX (optionnel):" -ForegroundColor Gray
    Write-Host "  upx --best --lzma $exe" -ForegroundColor Yellow
}
