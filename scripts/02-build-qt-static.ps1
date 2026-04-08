#!/usr/bin/env pwsh
#Requires -Version 5.1
<#
.SYNOPSIS
    Télécharge les sources Qt, détecte les flags disponibles via
    configure.bat -help, puis compile et installe une Qt 6 statique
    pour Windows x64 / MSVC 2022.

.DESCRIPTION
    Étapes réalisées :
      1. Téléchargement de l'archive sources Qt (avec barre de progression).
      2. Extraction via 7-Zip.
      3. Détection automatique des flags configure.bat : les flags qui
         n'existent pas dans la version choisie (ex. -no-emojisegmenter
         absent sur Qt >= 6.9) sont silencieusement omis.
      4. Écriture d'un .bat temporaire pour invoquer configure sans
         problèmes de guillemets PowerShell→cmd.
      5. Build Ninja (Release, parallèle).
      6. Installation dans le préfixe choisi.

    L'invocation de configure.bat suit la convention Qt 6 :
      - Exécution depuis le répertoire SOURCE avec le flag -B <builddir>.
      - Ainsi Qt peut retrouver ses propres sous-modules.

    Si le préfixe d'installation contient déjà Qt6Config.cmake le script
    se termine immédiatement (aucun rebuild inutile).

.PARAMETER QtVersion
    Version Qt à télécharger/compiler. Défaut : 6.9.2

.PARAMETER InstallPrefix
    Répertoire d'installation finale. Défaut : C:\Qt\static\Qt-<version>

.PARAMETER DownloadDir
    Répertoire temporaire (téléchargement + extraction). Défaut : %TEMP%\qt-src

.PARAMETER Jobs
    Nombre de threads de compilation. Défaut : nombre de cœurs logiques.

.PARAMETER DisableDeprecatedUpTo
    Valeur passée à -disable-deprecated-up-to (si le flag est disponible).
    Défaut : 0x060800 (cohérent avec QT_DISABLE_DEPRECATED_UP_TO du projet).

.PARAMETER SkipDownload
    Ne pas re-télécharger si l'archive existe déjà.

.PARAMETER SkipExtract
    Ne pas re-extraire si le répertoire source existe déjà.

.EXAMPLE
    # Build Qt 6.9.2 avec les paramètres par défaut
    .\02-build-qt-static.ps1

    # Qt 6.9.2, préfixe et download personnalisés
    .\02-build-qt-static.ps1 -QtVersion 6.9.2 -InstallPrefix D:\Qt\static\Qt-6.9.2

    # Reprendre un build interrompu (sources déjà là)
    .\02-build-qt-static.ps1 -SkipDownload -SkipExtract
#>
param(
    [string] $QtVersion             = '6.9.2',
    [string] $InstallPrefix         = '',
    [string] $DownloadDir           = "$env:TEMP\qt-src",
    [int]    $Jobs                  = [Environment]::ProcessorCount,
    [string] $DisableDeprecatedUpTo = '0x060800',
    [switch] $SkipDownload,
    [switch] $SkipExtract
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

# Active l'environnement VS 2022 x64 si cl.exe n'est pas sur le PATH.
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
        Fail "Visual Studio 2022 avec le workload Desktop C++ non trouvé. Installez-le depuis https://visualstudio.microsoft.com/"
    }

    $vcvars = "$vsPath\VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path $vcvars)) {
        Fail "vcvars64.bat introuvable : $vcvars"
    }

    Write-Host "  Activation VS : $vcvars" -ForegroundColor DarkGray
    # Importer les variables d'environnement VS dans la session PowerShell courante.
    cmd /c """$vcvars"" && set" 2>$null | ForEach-Object {
        if ($_ -match '^([^=]+)=(.*)$') {
            [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2], 'Process')
        }
    }
}

# Trouve 7z.exe dans les emplacements courants.
function Get-7z {
    foreach ($p in @(
        (Get-Command '7z' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
        'C:\Program Files\7-Zip\7z.exe',
        'C:\Program Files (x86)\7-Zip\7z.exe'
    )) {
        if ($p -and (Test-Path $p)) { return $p }
    }
    Fail "7-Zip introuvable. Installez-le depuis https://www.7-zip.org/ ou lancez 01-check-prerequisites.ps1 -Fix"
}

# Téléchargement avec barre de progression console.
function Download-File([string]$Uri, [string]$OutFile) {
    Write-Host "  URL : $Uri" -ForegroundColor DarkGray
    Write-Host "  →   $OutFile" -ForegroundColor DarkGray

    $wc = New-Object System.Net.WebClient
    $script:lastPct = -1
    $wc.add_DownloadProgressChanged({
        param($s, $e)
        $pct = $e.ProgressPercentage
        if ($pct -ne $script:lastPct -and $pct % 5 -eq 0) {
            $script:lastPct = $pct
            $mb  = [math]::Round($e.BytesReceived / 1MB, 1)
            $tot = if ($e.TotalBytesToReceive -gt 0) { [math]::Round($e.TotalBytesToReceive / 1MB, 0) } else { '?' }
            Write-Host ("`r  $pct %   $mb MB / $tot MB  ") -NoNewline -ForegroundColor DarkGray
        }
    })
    $task = $wc.DownloadFileTaskAsync($Uri, $OutFile)
    while (-not $task.IsCompleted) { Start-Sleep -Milliseconds 250 }
    Write-Host ''
    if ($task.IsFaulted) { Fail "Téléchargement échoué : $($task.Exception.InnerException.Message)" }
}

# Construit une ligne de commande cmd correctement quotée.
# Chaque argument contenant un espace est entouré de guillemets doubles.
function Build-CmdLine([string]$Exe, [string[]]$ArgList) {
    $parts = @($Exe)
    foreach ($a in $ArgList) {
        if ($a -match '\s') { $parts += "`"$a`"" }
        else                { $parts += $a }
    }
    return $parts -join ' '
}

# Exécute une commande via un .bat temporaire (évite les problèmes de
# guillemets PowerShell → cmd) depuis un répertoire donné.
# Retourne le code de sortie.
function Invoke-BatchCmd([string]$WorkDir, [string]$CmdLine) {
    $bat = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.bat'
    try {
        @(
            '@echo off',
            "cd /d `"$WorkDir`"",
            $CmdLine,
            'exit /b %ERRORLEVEL%'
        ) | Set-Content -Path $bat -Encoding ASCII

        cmd /c $bat
        return $LASTEXITCODE
    } finally {
        Remove-Item $bat -ErrorAction SilentlyContinue
    }
}

# ── Chemins dérivés ───────────────────────────────────────────────────────────

$qtMajMin = ($QtVersion -split '\.')[0..1] -join '.'   # ex : "6.9"
if (-not $InstallPrefix) {
    $InstallPrefix = "C:\Qt\static\Qt-$QtVersion"
}

$srcBaseName = "qt-everywhere-src-$QtVersion"
$qtSrcDir    = Join-Path $DownloadDir $srcBaseName
$qtTarFile   = Join-Path $DownloadDir "$srcBaseName.tar.xz"
$qtBuildDir  = Join-Path $DownloadDir "qt-build-$QtVersion"

$downloadUrl = "https://download.qt.io/official_releases/qt/$qtMajMin/$QtVersion/single/$srcBaseName.tar.xz"

# ── Affichage de la configuration ─────────────────────────────────────────────

Write-Host ''
Write-Host 'Qt Static Build — rpgmtranslate-qt' -ForegroundColor Cyan
Write-Host ('=' * 60) -ForegroundColor Cyan
Write-Host "  Version Qt     : $QtVersion"
Write-Host "  Préfixe install: $InstallPrefix"
Write-Host "  Répertoire tmp : $DownloadDir"
Write-Host "  Jobs Ninja     : $Jobs"
Write-Host ''

# ── Vérification idempotence ──────────────────────────────────────────────────

$marker = Join-Path $InstallPrefix 'lib\cmake\Qt6\Qt6Config.cmake'
if (Test-Path $marker) {
    Write-Host "✔  Qt $QtVersion déjà installé dans $InstallPrefix" -ForegroundColor Green
    Write-Host "   Supprimez '$InstallPrefix' pour forcer un rebuild." -ForegroundColor DarkGray
    exit 0
}

# ── Prérequis ─────────────────────────────────────────────────────────────────

Ensure-VsEnv
$7z = Get-7z

foreach ($tool in @('cmake', 'ninja')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        Fail "'$tool' absent du PATH. Lancez 01-check-prerequisites.ps1 pour vérifier les prérequis."
    }
}

New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 1 — Téléchargement
# ════════════════════════════════════════════════════════════════════════════
Write-Step "Téléchargement Qt $QtVersion (~500 MB)"

if ($SkipDownload -and (Test-Path $qtTarFile)) {
    Write-Host "  [skip] Archive déjà présente : $qtTarFile" -ForegroundColor DarkGray
} else {
    Download-File -Uri $downloadUrl -OutFile $qtTarFile
    $sizeMB = [math]::Round((Get-Item $qtTarFile).Length / 1MB, 0)
    Write-Host "  ✔ Téléchargement terminé : $sizeMB MB" -ForegroundColor Green
}

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 2 — Extraction
# ════════════════════════════════════════════════════════════════════════════
Write-Step "Extraction des sources (plusieurs minutes)"

if ($SkipExtract -and (Test-Path $qtSrcDir)) {
    Write-Host "  [skip] Répertoire source déjà présent : $qtSrcDir" -ForegroundColor DarkGray
} else {
    if (Test-Path $qtSrcDir) {
        Write-Host "  Suppression de l'ancienne extraction…" -ForegroundColor DarkGray
        Remove-Item $qtSrcDir -Recurse -Force
    }
    Write-Host "  Lancement de 7-Zip…" -ForegroundColor DarkGray
    & $7z x $qtTarFile "-o$DownloadDir" -y 2>&1 | ForEach-Object {
        if ($_ -match 'Everything') { Write-Host "  $_" -ForegroundColor DarkGray }
    }
    if (-not (Test-Path $qtSrcDir)) {
        Fail "Extraction échouée : le répertoire '$qtSrcDir' n'a pas été créé."
    }
    Write-Host "  ✔ Extraction terminée : $qtSrcDir" -ForegroundColor Green
}

if (-not (Test-Path (Join-Path $qtSrcDir 'configure.bat'))) {
    Fail "configure.bat introuvable dans '$qtSrcDir'. Vérifiez l'extraction."
}

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 3 — Détection des flags configure.bat
# ════════════════════════════════════════════════════════════════════════════
Write-Step "Détection des flags configure.bat disponibles (~30 s)"

# configure.bat -help est lancé depuis le répertoire source.
# Qt 6 utilise son propre emplacement (%~dp0) comme racine source.
# On capture stdout+stderr pour analyser les flags disponibles.
$helpText = (cmd /c "cd /d `"$qtSrcDir`" && configure.bat -help 2>&1") -join "`n"

function Has-Flag([string]$F) { $helpText -match [regex]::Escape($F) }

$hasCxxStdSpace  = Has-Flag '-c++std c++23'      # Qt <= 6.8 : deux tokens séparés
$hasCxxStdEqual  = Has-Flag '-c++std=c++23'      # forme alternative
$hasNoEmoji      = Has-Flag '-no-emojisegmenter' # absent Qt >= 6.9
$hasLtcg         = Has-Flag '-ltcg'
$hasDisableDepr  = Has-Flag '-disable-deprecated-up-to'
$hasSubmodules   = Has-Flag '-submodules'

Write-Host "  -c++std c++23 (espace)     : $(if ($hasCxxStdSpace)  {'OUI'} else {'non (ignoré)'})"
Write-Host "  -c++std=c++23 (=)          : $(if ($hasCxxStdEqual)  {'OUI'} else {'non (ignoré)'})"
Write-Host "  -no-emojisegmenter         : $(if ($hasNoEmoji)      {'OUI'} else {'non (ignoré)'})"
Write-Host "  -ltcg                      : $(if ($hasLtcg)         {'OUI'} else {'non (ignoré)'})"
Write-Host "  -disable-deprecated-up-to  : $(if ($hasDisableDepr)  {'OUI'} else {'non (ignoré)'})"
Write-Host "  -submodules                : $(if ($hasSubmodules)   {'OUI'} else {'non (ignoré)'})"

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 4 — Construction de la commande configure
# ════════════════════════════════════════════════════════════════════════════
Write-Step "Préparation de la commande configure"

New-Item -ItemType Directory -Force -Path $qtBuildDir | Out-Null

# Arguments configure.bat.
# Convention Qt 6 : configure.bat lancé depuis le répertoire SOURCE,
# avec -B <builddir> pour spécifier le répertoire de build out-of-source.
$cfgArgs = [System.Collections.Generic.List[string]]@(
    '-B',           $qtBuildDir,
    '-platform',    'win32-msvc',
    '-static',
    '-static-runtime',
    '-release',
    '-prefix',      $InstallPrefix,
    '-nomake',      'tests',
    '-nomake',      'examples',
    '-nomake',      'benchmarks',
    '-no-feature-testlib',
    '-no-opengl',
    '-qt-harfbuzz',
    '-qt-freetype',
    '-qt-libpng',
    '-qt-libjpeg',
    '-qt-webp',
    '-qt-tiff',
    '-qt-zlib',
    '-qt-doubleconversion',
    '-qt-pcre',
    '-no-icu',
    '-no-gif',
    '-gui',
    '-widgets',
    '-qpa', 'windows'
)

if ($hasSubmodules) {
    # qtsvg requis par CMakeLists.txt (Qt6::Svg)
    # qttools requis pour LinguistTools (lupdate / lrelease)
    $cfgArgs.AddRange([string[]]@('-submodules', 'qtbase,qtsvg,qtimageformats,qttools'))
}

if ($hasCxxStdSpace) {
    $cfgArgs.AddRange([string[]]@('-c++std', 'c++23'))
} elseif ($hasCxxStdEqual) {
    $cfgArgs.Add('-c++std=c++23')
}

if ($hasNoEmoji)     { $cfgArgs.Add('-no-emojisegmenter') }
if ($hasLtcg)        { $cfgArgs.Add('-ltcg') }
if ($hasDisableDepr) { $cfgArgs.AddRange([string[]]@('-disable-deprecated-up-to', $DisableDeprecatedUpTo)) }

# Options CMake passées après '--'
$cfgArgs.AddRange([string[]]@('--', '-DQT_SKIP_EXCEPTIONS=ON'))

$cmdLine = Build-CmdLine 'configure.bat' $cfgArgs
Write-Host "  $cmdLine" -ForegroundColor DarkGray

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 5 — Configure
# ════════════════════════════════════════════════════════════════════════════
Write-Step "Configure Qt (Ninja + MSVC — ~5–15 min)"

$rc = Invoke-BatchCmd -WorkDir $qtSrcDir -CmdLine $cmdLine
if ($rc -ne 0) {
    Fail "configure.bat a échoué (code $rc). Vérifiez les messages ci-dessus."
}
Write-Host "  ✔ Configure réussi." -ForegroundColor Green

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 6 — Build
# ════════════════════════════════════════════════════════════════════════════
Write-Step "Build Qt (Ninja, $Jobs jobs — 30 à 90 minutes selon le CPU)"

Push-Location $qtBuildDir
try {
    cmake --build . --parallel $Jobs
    if ($LASTEXITCODE -ne 0) { Fail "cmake --build a échoué (code $LASTEXITCODE)." }
} finally {
    Pop-Location
}
Write-Host "  ✔ Build réussi." -ForegroundColor Green

# ════════════════════════════════════════════════════════════════════════════
# ÉTAPE 7 — Install
# ════════════════════════════════════════════════════════════════════════════
Write-Step "Installation dans $InstallPrefix"

Push-Location $qtBuildDir
try {
    cmake --install .
    if ($LASTEXITCODE -ne 0) { Fail "cmake --install a échoué (code $LASTEXITCODE)." }
} finally {
    Pop-Location
}

if (-not (Test-Path $marker)) {
    Fail "Vérification post-install échouée : '$marker' introuvable."
}

Write-Host ''
Write-Host ('=' * 60) -ForegroundColor Green
Write-Host "✔  Qt $QtVersion installé avec succès :" -ForegroundColor Green
Write-Host "   $InstallPrefix" -ForegroundColor Green
Write-Host ''
Write-Host "Étape suivante :" -ForegroundColor Cyan
Write-Host "   .\scripts\03-build-rpgmtranslate.ps1 -QtRoot `"$InstallPrefix`"" -ForegroundColor Cyan
Write-Host ''
