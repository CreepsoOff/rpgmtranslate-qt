#!/usr/bin/env pwsh
# 01-check-prerequisites.ps1
# Verifie et installe les prerequis pour builder rpgmtranslate-qt.
# Setup identique au developpeur upstream: VS Build Tools 2026 + LLVM/clang-cl.
# A executer en PowerShell ADMIN.

$ErrorActionPreference = "Stop"

# ── Auto-elevation (relance en admin si nécessaire) ─────────────────
$currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Demande d'elevation des privileges..." -ForegroundColor Yellow

    try {
        $process = Start-Process powershell `
            -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" `
            -Verb RunAs `
            -PassThru

        exit
    } catch {
        Write-Host "Execution annulee : le script necessite les droits administrateur." -ForegroundColor Red
        exit 1
    }
}

function Test-Command($cmd) {
    return [bool](Get-Command $cmd -ErrorAction SilentlyContinue)
}

function Confirm-OrProvide {
    param(
        [string]$Name,
        [string]$DetectedPath,
        [string]$ValidationFile,
        [scriptblock]$InstallAction
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

    $options = @("[1] Specifier le chemin manuellement")
    if ($InstallAction) { $options += "[2] Installer automatiquement" }
    $options += "[0] Passer (ne rien faire)"

    Write-Host ""
    $options | ForEach-Object { Write-Host "  $_" -ForegroundColor White }
    Write-Host ""

    $validChoices = @("0", "1")
    if ($InstallAction) { $validChoices += "2" }

    do {
        $choice = Read-Host "  Choix"
    } while ($choice -notin $validChoices)

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
# 1. VS Build Tools 2026 (strict: BuildTools product, version 18.x)
# ══════════════════════════════════════════════════════════════════════
Write-Host "--- 1. Visual Studio Build Tools 2026 ---" -ForegroundColor Cyan
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsDetected = $null
$vsDisplay = ""
$vsVersion = ""

if (Test-Path $vsWhere) {
    $vsDetected = & $vsWhere `
        -products Microsoft.VisualStudio.Product.BuildTools `
        -version "[18.0,19.0)" `
        -latest `
        -property installationPath 2>$null
    $vsVersion = & $vsWhere `
        -products Microsoft.VisualStudio.Product.BuildTools `
        -version "[18.0,19.0)" `
        -latest `
        -property installationVersion 2>$null
    $vsDisplay = & $vsWhere `
        -products Microsoft.VisualStudio.Product.BuildTools `
        -version "[18.0,19.0)" `
        -latest `
        -property displayName 2>$null
}

$vsLabel = if ($vsDisplay) { "$vsDisplay (v$vsVersion)" } else { "Visual Studio Build Tools 2026" }
Confirm-OrProvide `
    -Name $vsLabel `
    -DetectedPath $vsDetected `
    -ValidationFile "VC\Auxiliary\Build\vcvarsall.bat" `
    -InstallAction {
        winget install -e --id Microsoft.VisualStudio.BuildTools --source winget `
            --override "--wait --passive --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
        Write-Host "  >> Redemarre ce script apres installation." -ForegroundColor Yellow
    } | Out-Null

# ══════════════════════════════════════════════════════════════════════
# 2. LLVM / clang-cl
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- 2. LLVM / clang-cl ---" -ForegroundColor Cyan
$llvmDetected = $null
foreach ($p in @("${env:ProgramFiles}\LLVM", "${env:ProgramFiles(x86)}\LLVM")) {
    if (Test-Path "$p\bin\clang-cl.exe") { $llvmDetected = $p; break }
}
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
    -ValidationFile "cmd\git.exe" `
    -InstallAction {
        winget install -e --id Git.Git --source winget
    } | Out-Null

# ══════════════════════════════════════════════════════════════════════
# 4. CMake (FORCE 3.31.11 — CMake 4.x casse le link de linguist.exe)
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- 4. CMake (3.31.11 requis) ---" -ForegroundColor Cyan

$cmakeRequired = "3.31.11"
$cmakeMsiUrl   = "https://github.com/Kitware/CMake/releases/download/v$cmakeRequired/cmake-$cmakeRequired-windows-x86_64.msi"

function Get-CMake-Version {
    param([string]$CmakeCommand = "cmake")
    try {
        $firstLine = (& $CmakeCommand --version 2>$null | Select-Object -First 1)
        if ($firstLine -match "cmake version (\d+)\.(\d+)\.(\d+)") {
            return [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
        }
    } catch {}
    return $null
}

function Install-CMake-3-31-11 {
    $msi = "$env:TEMP\cmake-$cmakeRequired-windows-x86_64.msi"
    Write-Host "  Telechargement CMake $cmakeRequired..." -ForegroundColor Cyan
    Write-Host "    $cmakeMsiUrl" -ForegroundColor Gray
    Invoke-WebRequest -Uri $cmakeMsiUrl -OutFile $msi -UseBasicParsing
    Write-Host "  Installation MSI (silencieux, ajout au PATH systeme)..." -ForegroundColor Cyan
    $proc = Start-Process msiexec.exe `
        -ArgumentList "/i `"$msi`" /qn /norestart ADD_CMAKE_TO_PATH=System" `
        -Wait -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Host "  ERREUR: msiexec exit code $($proc.ExitCode)" -ForegroundColor Red
        return $false
    } else {
        $cmakeBinDir = "${env:ProgramFiles}\CMake\bin"
        if ((Test-Path "$cmakeBinDir\cmake.exe") -and ($env:Path -notlike "*$cmakeBinDir*")) {
            $env:Path = "$cmakeBinDir;$env:Path"
        }
        Write-Host "  OK." -ForegroundColor Green
        return $true
    }
}

$cmakeTarget = [version]$cmakeRequired
$cmakeVersion = Get-CMake-Version
$needInstall = $false

if ($cmakeVersion -eq $cmakeTarget) {
    Write-Host "[OK] CMake $cmakeRequired present" -ForegroundColor Green
} elseif ($cmakeVersion -ne $null -and $cmakeVersion.Major -ge 4) {
    Write-Host "[ATTENTION] CMake $cmakeVersion detecte. Bug connu sur le link de Qt linguist.exe." -ForegroundColor Red
    Write-Host "  Il faut downgrade vers $cmakeRequired." -ForegroundColor Yellow
    $confirm = Read-Host "  Desinstaller CMake actuel et installer $cmakeRequired ? (O/n)"
    if ($confirm -eq "" -or $confirm -match "^[oOyY]") {
        $needInstall = $true
    } else {
        Write-Host "  ERREUR: CMake $cmakeRequired est obligatoire." -ForegroundColor Red
        exit 1
    }
} elseif ($cmakeVersion -ne $null) {
    Write-Host "[WARN] CMake $cmakeVersion present (attendu: $cmakeRequired)" -ForegroundColor Yellow
    $confirm = Read-Host "  Remplacer par $cmakeRequired ? (O/n)"
    if ($confirm -eq "" -or $confirm -match "^[oOyY]") {
        $needInstall = $true
    } else {
        Write-Host "  ERREUR: CMake $cmakeRequired est obligatoire." -ForegroundColor Red
        exit 1
    }
} else {
    Write-Host "[NON TROUVE] CMake" -ForegroundColor Yellow
    $needInstall = $true
}

if ($needInstall) {
    winget uninstall -e --id Kitware.CMake 2>$null
    $ok = Install-CMake-3-31-11
    if (-not $ok) { exit 1 }
}

# Recheck strict et bloquant
$cmakeVersion = Get-CMake-Version
if ($cmakeVersion -ne $cmakeTarget) {
    $cmakeFallback = "${env:ProgramFiles}\CMake\bin\cmake.exe"
    if (Test-Path $cmakeFallback) {
        $cmakeVersion = Get-CMake-Version -CmakeCommand $cmakeFallback
        if ($cmakeVersion -eq $cmakeTarget -and ($env:Path -notlike "*${env:ProgramFiles}\CMake\bin*")) {
            $env:Path = "${env:ProgramFiles}\CMake\bin;$env:Path"
        }
    }
}

if ($cmakeVersion -ne $cmakeTarget) {
    Write-Host "ERREUR: CMake $cmakeRequired requis, version detectee: $cmakeVersion" -ForegroundColor Red
    exit 1
}

$cmakeExePath = (Get-Command cmake -ErrorAction SilentlyContinue).Source
Write-Host "[OK] CMake verrouille sur $cmakeVersion" -ForegroundColor Green
if ($cmakeExePath) {
    Write-Host "  Executable: $cmakeExePath" -ForegroundColor Gray
}

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
    -ValidationFile "ninja.exe" `
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
    -ValidationFile "python.exe" `
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

Confirm-OrProvide `
    -Name $rustLabel `
    -DetectedPath $rustDetected `
    -ValidationFile "rustc.exe" `
    -InstallAction {
        winget install -e --id Rustlang.Rustup --source winget
        Write-Host "  >> Ferme et rouvre PowerShell, puis relance ce script." -ForegroundColor Yellow
    } | Out-Null

# Configure MSVC target si Rust est present (sans changer le default global)
if (Test-Command "rustup") {
    $targets = rustup target list --installed 2>$null
    if (-not ($targets -match "x86_64-pc-windows-msvc")) {
        Write-Host "  Installation du toolchain et target MSVC x64..." -ForegroundColor Yellow
        rustup toolchain install stable-x86_64-pc-windows-msvc
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
    -ValidationFile "cbindgen.exe" `
    -InstallAction {
        cargo install cbindgen --version "0.29.2"
    } | Out-Null

# ══════════════════════════════════════════════════════════════════════
# 9. 7-Zip
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- 9. 7-Zip ---" -ForegroundColor Cyan
$szDetected = $null
foreach ($p in @("${env:ProgramFiles}\7-Zip", "${env:ProgramFiles(x86)}\7-Zip")) {
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
# 10. vcpkg (auto-detect VCPKG_ROOT -> C:\vcpkg -> F:\vcpkg)
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- 10. vcpkg ---" -ForegroundColor Cyan
$vcpkgDefaultInstall = "F:\vcpkg"
$vcpkgPath = $null

# Auto-detection prioritaire: VCPKG_ROOT -> C:\vcpkg -> F:\vcpkg
$vcpkgCandidates = @()
if ($env:VCPKG_ROOT) { $vcpkgCandidates += $env:VCPKG_ROOT }
$vcpkgCandidates += @("C:\vcpkg", "F:\vcpkg")
$vcpkgCandidates = $vcpkgCandidates | Where-Object { $_ } | Select-Object -Unique

foreach ($candidate in $vcpkgCandidates) {
    if (Test-Path "$candidate\vcpkg.exe") {
        $vcpkgPath = $candidate
        break
    }
}

if ($vcpkgPath) {
    Write-Host "[DETECTE] vcpkg" -ForegroundColor Green
    Write-Host "  Chemin: $vcpkgPath" -ForegroundColor Gray
    $confirm = Read-Host "  Utiliser ce chemin ? (O/n)"
    if (-not ($confirm -eq "" -or $confirm -match "^[oOyY]")) {
        $vcpkgPath = $null
    }
}

if (-not $vcpkgPath) {
    Write-Host "[NON TROUVE] vcpkg" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  [1] Specifier le chemin manuellement" -ForegroundColor White
    Write-Host "  [2] Installer automatiquement (F:\vcpkg)" -ForegroundColor White
    Write-Host "  [0] Passer (ne rien faire)" -ForegroundColor White
    Write-Host ""

    do {
        $choice = Read-Host "  Choix"
    } while ($choice -notin @("0", "1", "2"))

    switch ($choice) {
        "1" {
            do {
                $manual = (Read-Host "  Chemin vers vcpkg (dossier contenant vcpkg.exe)").Trim('"').Trim("'")
                if (Test-Path "$manual\vcpkg.exe") {
                    $vcpkgPath = $manual
                    Write-Host "  OK: $vcpkgPath" -ForegroundColor Green
                } else {
                    Write-Host "  vcpkg.exe introuvable dans '$manual'." -ForegroundColor Red
                    $manual = $null
                }
            } while (-not $manual)
        }
        "2" {
            if (-not (Test-Path "F:\")) {
                Write-Host "  ERREUR: F:\ inaccessible." -ForegroundColor Red
                exit 1
            }

            $target = $vcpkgDefaultInstall
            if (-not (Test-Path $target)) {
                git clone https://github.com/microsoft/vcpkg.git $target
            } elseif (-not (Test-Path "$target\.git")) {
                Write-Host "  ERREUR: '$target' existe deja mais n'est pas un depot vcpkg." -ForegroundColor Red
                exit 1
            }

            if (-not (Test-Path "$target\vcpkg.exe")) {
                & "$target\bootstrap-vcpkg.bat" -disableMetrics
            }

            if (Test-Path "$target\vcpkg.exe") {
                $vcpkgPath = $target
                Write-Host "  OK: $vcpkgPath" -ForegroundColor Green
            } else {
                Write-Host "  ERREUR: installation vcpkg echouee." -ForegroundColor Red
                exit 1
            }
        }
        "0" {
            Write-Host "  Passe." -ForegroundColor Gray
        }
    }
}

if ($vcpkgPath) {
    Write-Host "[OK] vcpkg retenu: $vcpkgPath" -ForegroundColor Green
} else {
    Write-Host "[WARN] vcpkg non configure. L'etape LibArchive sera ignoree." -ForegroundColor Yellow
}

# ══════════════════════════════════════════════════════════════════════
# 11. LibArchive (vcpkg, static)
# ══════════════════════════════════════════════════════════════════════
Write-Host ""
Write-Host "--- 11. LibArchive (x64-windows-static) ---" -ForegroundColor Cyan
if (-not $vcpkgPath) {
    Write-Host "[SKIP] LibArchive: vcpkg non configure." -ForegroundColor Yellow
} else {
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
