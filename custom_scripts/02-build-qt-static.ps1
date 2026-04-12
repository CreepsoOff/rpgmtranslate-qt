#!/usr/bin/env pwsh
# 02-build-qt-static.ps1
# Download/build/install a static Qt (Windows, MSVC x64 shell).
# Uses upstream command shape from docs/development.md.

param(
    [string]$QtVersion = "6.11.0",
    [string]$SourceRoot = "F:\dev",
    [string]$BuildDir = "",
    [string]$InstallDir = "",
    [int]$Jobs = 0
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Ensure-Tool([string]$ToolName) {
    if (-not (Get-Command $ToolName -ErrorAction SilentlyContinue)) {
        Fail "$ToolName is not available in PATH."
    }
}

function Ensure-QtArtifacts([string]$Root) {
    $checks = @(
        "$Root\bin\qmake.exe",
        "$Root\lib\cmake\Qt6Svg",
        "$Root\lib\cmake\Qt6LinguistTools"
    )

    foreach ($path in $checks) {
        if (-not (Test-Path $path)) {
            return $false
        }
    }

    return $true
}

function Download-File([string]$Url, [string]$OutFile) {
    Write-Host "Downloading: $Url" -ForegroundColor Cyan
    Invoke-WebRequest -Uri $Url -OutFile $OutFile
}

if ($BuildDir -eq "") {
    $BuildDir = "F:\dev\qt-build-$QtVersion-static"
}

if ($InstallDir -eq "") {
    $InstallDir = "F:\dev\qt-$QtVersion-static-msvc"
}

if (-not $env:VSINSTALLDIR) {
    Fail "Run this script inside Developer PowerShell / x64 Native Tools shell."
}

Ensure-Tool "cl"
Ensure-Tool "cmake"
Ensure-Tool "7z"

$clText = (cl 2>&1 | Out-String)
if ($clText -notmatch "x64|amd64") {
    Fail "cl.exe is not in x64 mode. Open an x64 Native Tools shell first."
}

if (Ensure-QtArtifacts $InstallDir) {
    Write-Host "Qt static install already present and complete: $InstallDir" -ForegroundColor Green
    exit 0
}

New-Item -ItemType Directory -Force -Path $SourceRoot | Out-Null
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

$srcDir = "$SourceRoot\qt-src-$QtVersion"
$zipName = "qt-everywhere-src-$QtVersion.zip"
$zipPath = "$SourceRoot\$zipName"
$majorMinor = $QtVersion.Substring(0, 4)
$downloadUrl = "https://download.qt.io/official_releases/qt/$majorMinor/$QtVersion/single/$zipName"

if (-not (Test-Path "$srcDir\configure.bat")) {
    if (-not (Test-Path $zipPath)) {
        Download-File -Url $downloadUrl -OutFile $zipPath
    }

    Write-Host "Extracting Qt sources..." -ForegroundColor Cyan
    7z x $zipPath "-o$SourceRoot" -y | Out-Null

    $extractedDir = "$SourceRoot\qt-everywhere-src-$QtVersion"
    if (-not (Test-Path "$extractedDir\configure.bat")) {
        Fail "Qt source extraction failed: configure.bat not found in $extractedDir"
    }

    if ($extractedDir -ne $srcDir) {
        if (Test-Path $srcDir) {
            Remove-Item -Recurse -Force $srcDir
        }

        Rename-Item -Path $extractedDir -NewName (Split-Path $srcDir -Leaf)
    }
}

if (-not (Test-Path "$srcDir\configure.bat")) {
    Fail "Qt source directory is invalid: $srcDir"
}

if ($Jobs -le 0) {
    $Jobs = [Math]::Max(1, [Environment]::ProcessorCount - 1)
}

Set-Location $BuildDir

$qtConfigureArgs = @(
    "-prefix", $InstallDir,
    "-no-guess-compiler",
    "-cmake-use-default-generator",
    "-c++std", "c++23",
    "-release",
    "-static",
    "-static-runtime",
    "-ltcg",
    "-reduce-relocations",
    "-nomake", "tests",
    "-nomake", "examples",
    "-nomake", "benchmarks",
    "-no-opengl",
    "-no-emojisegmenter",
    "-no-appstore-compliant",
    "-no-sbom",
    "-no-sbom-json",
    "-no-sbom-verify",
    "-no-icu",
    "-no-gif",
    "-no-dbus",
    "-no-schannel",
    "-no-system-proxies",
    "-no-mimetype-database",
    "-qt-harfbuzz",
    "-qt-freetype",
    "-qt-libpng",
    "-qt-libjpeg",
    "-qt-webp",
    "-qt-tiff",
    "-qt-zlib",
    "-qt-doubleconversion",
    "-qt-pcre",
    "-gui",
    "-widgets",
    "-submodules", "qtbase,qtimageformats,qttools,qtsvg",
    "-qpa", "windows"
)

Write-Host "Configuring Qt $QtVersion..." -ForegroundColor Cyan
& "$srcDir\configure.bat" @qtConfigureArgs
if ($LASTEXITCODE -ne 0) {
    Fail "Qt configure failed."
}

Write-Host "Building Qt ($Jobs jobs)..." -ForegroundColor Cyan
cmake --build . --parallel $Jobs
if ($LASTEXITCODE -ne 0) {
    Fail "Qt build failed."
}

Write-Host "Installing Qt..." -ForegroundColor Cyan
cmake --install .
if ($LASTEXITCODE -ne 0) {
    Fail "Qt install failed."
}

if (-not (Ensure-QtArtifacts $InstallDir)) {
    Fail "Qt install is incomplete (missing qmake / Qt6Svg / Qt6LinguistTools)."
}

Write-Host "Qt static build is ready: $InstallDir" -ForegroundColor Green