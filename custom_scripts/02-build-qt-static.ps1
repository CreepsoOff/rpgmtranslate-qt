#!/usr/bin/env pwsh
# 02-build-qt-static.ps1
# Telecharge et build Qt 6.11.0 en statique pour MSVC.
# A executer UNE SEULE FOIS dans "Developer PowerShell for VS 2022/2026".
# Prend environ 30-60 minutes selon le CPU.

param(
    [string]$QtVersion  = "6.11.0",
    [string]$BuildDir   = "F:\dev\qt-build-$QtVersion-static",
    [string]$InstallDir = "F:\dev\qt-$QtVersion-static-msvc",
    [switch]$EnableLTCG
)

$ErrorActionPreference = "Stop"

function Test-QtInstallArtifacts {
    param(
        [string]$Root,
        [switch]$Verbose
    )

    $checks = @(
        @{ Label = "qmake.exe";            Path = "$Root\bin\qmake.exe" },
        @{ Label = "Qt6Svg package";       Path = "$Root\lib\cmake\Qt6Svg" },
        @{ Label = "Qt6LinguistTools";     Path = "$Root\lib\cmake\Qt6LinguistTools" }
    )

    $missing = @()
    foreach ($check in $checks) {
        if (Test-Path $check.Path) {
            if ($Verbose) {
                Write-Host "[OK] $($check.Label): $($check.Path)" -ForegroundColor Green
            }
        } else {
            $missing += $check
            if ($Verbose) {
                Write-Host "[MANQUANT] $($check.Label): $($check.Path)" -ForegroundColor Red
            }
        }
    }

    return $missing
}

# ── Verifier qu'on est dans un shell MSVC ────────────────────────────
if (-not $env:VSINSTALLDIR) {
    Write-Host "ERREUR: Ce script doit etre lance depuis 'Developer PowerShell for VS'." -ForegroundColor Red
    Write-Host "Ouvre-le via le menu Demarrer (Developer PowerShell for VS 2026 ou 2022)." -ForegroundColor Yellow
    exit 1
}

if (-not (Get-Command cl -ErrorAction SilentlyContinue)) {
    Write-Host "ERREUR: cl.exe introuvable. Verifie que tu es dans le bon shell MSVC x64." -ForegroundColor Red
    exit 1
}

# ── Verifier que cl.exe est en mode x64 (pas x86) ───────────────────
$clOutput = (cl 2>&1 | Out-String)
if ($clOutput -notmatch "x64|amd64") {
    Write-Host "ERREUR: cl.exe est en mode x86. Qt 6.11 requiert x64." -ForegroundColor Red
    Write-Host "  Utilise 'x64 Native Tools Command Prompt for VS 2026' puis tape 'pwsh'." -ForegroundColor Yellow
    Write-Host "  Ou lance: vcvarsall.bat x64" -ForegroundColor Yellow
    exit 1
}

# ── Verifier que 7-Zip est disponible ────────────────────────────────
$has7z = (Get-Command 7z -ErrorAction SilentlyContinue) -or `
         (Test-Path "${env:ProgramFiles}\7-Zip\7z.exe") -or `
         (Test-Path "${env:ProgramFiles(x86)}\7-Zip\7z.exe")

if (-not $has7z) {
    Write-Host "7-Zip est necessaire pour extraire les sources Qt." -ForegroundColor Yellow
    Write-Host "Installation..." -ForegroundColor Cyan
    winget install -e --id 7zip.7zip --source winget
    $env:Path = "${env:ProgramFiles}\7-Zip;$env:Path"
    if (-not (Get-Command 7z -ErrorAction SilentlyContinue)) {
        Write-Host "ERREUR: 7z introuvable apres installation. Relance le script." -ForegroundColor Red
        exit 1
    }
} elseif (-not (Get-Command 7z -ErrorAction SilentlyContinue)) {
    if (Test-Path "${env:ProgramFiles}\7-Zip\7z.exe") {
        $env:Path = "${env:ProgramFiles}\7-Zip;$env:Path"
    } else {
        $env:Path = "${env:ProgramFiles(x86)}\7-Zip;$env:Path"
    }
}

# ── Verifier si Qt statique est deja builde ──────────────────────────
if (Test-Path "$InstallDir\bin\qmake.exe") {
    Write-Host "Qt statique detecte dans $InstallDir, verification des artefacts..." -ForegroundColor Cyan
    $missing = Test-QtInstallArtifacts -Root $InstallDir -Verbose
    if ($missing.Count -eq 0) {
        Write-Host "Qt statique deja installe et complet dans $InstallDir" -ForegroundColor Green
        Write-Host "Supprime ce dossier si tu veux rebuilder." -ForegroundColor Gray
        exit 0
    } else {
        Write-Host "ERREUR: installation Qt existante incomplete/corrompue." -ForegroundColor Red
        Write-Host "Supprime '$InstallDir' puis relance le script." -ForegroundColor Yellow
        exit 1
    }
}

# ── Fonction: telechargement avec barre de progression ───────────────
function Download-WithProgress {
    param([string]$Url, [string]$OutFile)

    $uri = [System.Uri]::new($Url)
    $request = [System.Net.HttpWebRequest]::Create($uri)
    $request.Method = "GET"
    $request.Timeout = 30000
    $response = $request.GetResponse()
    $totalBytes = $response.ContentLength
    $stream = $response.GetResponseStream()
    $fileStream = [System.IO.File]::Create($OutFile)
    $buffer = New-Object byte[] 262144  # 256 Ko
    $downloaded = 0
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lastUpdate = 0

    try {
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $fileStream.Write($buffer, 0, $read)
            $downloaded += $read

            if ($sw.ElapsedMilliseconds - $lastUpdate -ge 500) {
                $lastUpdate = $sw.ElapsedMilliseconds
                $pct = if ($totalBytes -gt 0) { [math]::Round(($downloaded / $totalBytes) * 100, 1) } else { 0 }
                $dlMB = [math]::Round($downloaded / 1MB, 1)
                $totalMB = if ($totalBytes -gt 0) { [math]::Round($totalBytes / 1MB, 1) } else { "?" }
                $elapsed = $sw.Elapsed.TotalSeconds
                $speed = if ($elapsed -gt 0) { [math]::Round(($downloaded / 1MB) / $elapsed, 1) } else { 0 }

                $barLen = 30
                $filled = [math]::Floor($barLen * $pct / 100)
                $empty = $barLen - $filled
                $bar = ("#" * $filled) + ("-" * $empty)

                Write-Host "`r  [$bar] ${pct}%  ${dlMB} Mo / ${totalMB} Mo  (${speed} Mo/s)   " -NoNewline
            }
        }
    } finally {
        $fileStream.Close()
        $stream.Close()
        $response.Close()
    }

    $finalMB = [math]::Round($downloaded / 1MB, 1)
    $totalSec = [math]::Round($sw.Elapsed.TotalSeconds, 0)
    Write-Host "`r  [##############################] 100%  ${finalMB} Mo  en ${totalSec}s                    "
}

# ── Creer les dossiers ───────────────────────────────────────────────
foreach ($dir in @("F:\dev", $BuildDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}

# ── Localiser ou telecharger les sources Qt ──────────────────────────
$SrcDir = $null
$defaultSrcDir = "F:\dev\qt-src-$QtVersion"

if (Test-Path "$defaultSrcDir\configure.bat") {
    Write-Host "Sources Qt trouvees dans $defaultSrcDir" -ForegroundColor Green
    $SrcDir = $defaultSrcDir
}

if (-not $SrcDir) {
    Write-Host ""
    Write-Host "Les sources Qt $QtVersion sont necessaires pour builder Qt en statique." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  [1] Telecharger automatiquement (~1 Go)" -ForegroundColor White
    Write-Host "  [2] J'ai deja les sources, je donne le chemin" -ForegroundColor White
    Write-Host ""

    do {
        $choice = Read-Host "Choix (1 ou 2)"
    } while ($choice -notin @("1", "2"))

    if ($choice -eq "2") {
        do {
            $customPath = Read-Host "Chemin vers les sources Qt (dossier contenant configure.bat)"
            $customPath = $customPath.Trim('"').Trim("'")

            if (Test-Path "$customPath\configure.bat") {
                $SrcDir = $customPath
                Write-Host "Sources Qt trouvees dans $SrcDir" -ForegroundColor Green
            } else {
                Write-Host "configure.bat introuvable dans '$customPath'. Reessaie." -ForegroundColor Red
            }
        } while (-not $SrcDir)

    } else {
        $majorMinor = $QtVersion.Substring(0, 4)
        $zipName = "qt-everywhere-src-$QtVersion.zip"
        $url = "https://download.qt.io/official_releases/qt/$majorMinor/$QtVersion/single/$zipName"
        $zipPath = "F:\dev\$zipName"

        if (-not (Test-Path $zipPath)) {
            Write-Host ""
            Write-Host "Telechargement de Qt $QtVersion..." -ForegroundColor Cyan
            Write-Host "  $url" -ForegroundColor Gray
            Write-Host ""
            Download-WithProgress -Url $url -OutFile $zipPath
        } else {
            $sizeMB = [math]::Round((Get-Item $zipPath).Length / 1MB, 1)
            Write-Host "Archive deja presente: $zipPath ($sizeMB Mo)" -ForegroundColor Green
        }

        Write-Host ""
        Write-Host "Extraction des sources (ca peut prendre quelques minutes)..." -ForegroundColor Cyan
        7z x $zipPath -o"F:\dev" -y | Out-Null

        $extracted = "F:\dev\qt-everywhere-src-$QtVersion"
        if ((Test-Path $extracted) -and ($extracted -ne $defaultSrcDir)) {
            if (Test-Path $defaultSrcDir) { Remove-Item $defaultSrcDir -Recurse -Force }
            Rename-Item $extracted $defaultSrcDir
        }

        if (-not (Test-Path "$defaultSrcDir\configure.bat")) {
            Write-Host "ERREUR: configure.bat introuvable apres extraction dans $defaultSrcDir" -ForegroundColor Red
            exit 1
        }

        $SrcDir = $defaultSrcDir
        Write-Host "Sources extraites dans $SrcDir" -ForegroundColor Green
    }
}

# ── Configurer Qt ────────────────────────────────────────────────────
Write-Host ""
Write-Host "Configuration de Qt $QtVersion statique..." -ForegroundColor Cyan
Write-Host "  Sources:  $SrcDir" -ForegroundColor Gray
Write-Host "  Build:    $BuildDir" -ForegroundColor Gray
Write-Host "  Install:  $InstallDir" -ForegroundColor Gray

Set-Location $BuildDir

# Si un build precedent existe sans install Qt valide, nettoyer completement le builddir
if ((Test-Path "$BuildDir\CMakeCache.txt") -and -not (Test-Path "$InstallDir\bin\qmake.exe")) {
    Write-Host "Build precedent detecte dans $BuildDir sans install Qt complete, nettoyage complet du builddir..." -ForegroundColor Yellow

    if ($BuildDir -match '^[A-Za-z]:\\$') {
        Write-Host "ERREUR: refus de nettoyer une racine de disque ($BuildDir)." -ForegroundColor Red
        exit 1
    }

    Get-ChildItem -LiteralPath $BuildDir -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Flags identiques au build.md upstream (valides pour Qt 6.9+)
# LTCG desactive par defaut pour eviter les erreurs MSVC C1002/LNK1257 sur ce setup.
$qtConfigureArgs = @(
    "-prefix", $InstallDir,
    "-c++std", "c++23",
    "-platform", "win32-msvc",
    "-static",
    "-static-runtime",
    "-release",
    "-nomake", "tests",
    "-nomake", "examples",
    "-nomake", "benchmarks",
    "-no-feature-testlib",
    "-no-feature-assistant",
    "-no-opengl",
    "-qt-harfbuzz",
    "-qt-freetype",
    "-qt-libpng",
    "-qt-libjpeg",
    "-qt-webp",
    "-qt-tiff",
    "-qt-zlib",
    "-qt-doubleconversion",
    "-qt-pcre",
    "-no-emojisegmenter",
    "-no-icu",
    "-no-gif",
    "-gui",
    "-widgets",
    "-skip", "qtactiveqt",
    "-skip", "qtlanguageserver",
    "-skip", "qtshadertools",
    "-skip", "qtdeclarative",
    "-submodules", "qtbase,qtimageformats,qttools,qtsvg",
    "-qpa", "windows",
    "-disable-deprecated-up-to", "0x060802",
    "QT_SKIP_EXCEPTIONS=ON",
    "--",
    "-DBUILD_qtdeclarative=OFF",
    "-DBUILD_qtactiveqt=OFF",
    "-DBUILD_qtlanguageserver=OFF",
    "-DBUILD_qtshadertools=OFF"
)

if ($EnableLTCG) {
    Write-Host "LTCG active (--EnableLTCG)." -ForegroundColor Yellow
    $qtConfigureArgs += "-ltcg"
} else {
    Write-Host "LTCG desactive (defaut) pour stabilite du build." -ForegroundColor Yellow
}

& "$SrcDir\configure.bat" @qtConfigureArgs

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERREUR: configure.bat a echoue." -ForegroundColor Red
    exit 1
}

# ── Build ────────────────────────────────────────────────────────────
Write-Host ""
# On limite a (nb cores - 2) pour eviter la surchauffe CPU
$cores = [Math]::Max(1, (Get-CimInstance Win32_Processor).NumberOfLogicalProcessors - 2)
Write-Host "Build de Qt ($cores threads, ca prend un moment)..." -ForegroundColor Cyan

cmake --build . --parallel $cores
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERREUR: Le build Qt a echoue." -ForegroundColor Red
    exit 1
}

# ── Install ──────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Installation dans $InstallDir..." -ForegroundColor Cyan

cmake --install .
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERREUR: L'installation Qt a echoue." -ForegroundColor Red
    exit 1
}

# ── Verification stricte des artefacts requis ────────────────────────
Write-Host ""
Write-Host "Verification post-install Qt..." -ForegroundColor Cyan
$missing = Test-QtInstallArtifacts -Root $InstallDir -Verbose
if ($missing.Count -gt 0) {
    Write-Host "ERREUR: installation Qt incomplete. Artefacts manquants detectes." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Qt $QtVersion statique installe avec succes dans $InstallDir" -ForegroundColor Green
Write-Host ""
Write-Host "Tu peux maintenant builder rpgmtranslate-qt avec:" -ForegroundColor White
Write-Host "  .\03-build-rpgmtranslate.ps1" -ForegroundColor Yellow
