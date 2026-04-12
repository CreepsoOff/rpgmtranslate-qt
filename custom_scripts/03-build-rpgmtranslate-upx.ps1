#!/usr/bin/env pwsh
# 03-build-rpgmtranslate-upx.ps1
# Runs 03-build-rpgmtranslate.ps1, then compresses the executable with UPX.

param(
    [string]$RepoDir = "F:\Desktop\rpgmtranslate-qt",
    [string]$QtInstall = "F:\dev\qt-6.11.0-static-msvc",
    [string]$VcpkgRoot = "",
    [ValidateSet("Debug", "Release", "RelWithDebInfo", "MinSizeRel")]
    [string]$BuildType = "RelWithDebInfo",
    [switch]$Clean,
    [int]$Jobs = 0,
    [string[]]$UpxArgs = @("--best", "--lzma")
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

$buildScript = "$PSScriptRoot\03-build-rpgmtranslate.ps1"
if (-not (Test-Path $buildScript)) {
    Fail "Build script not found: $buildScript"
}

& $buildScript `
    -RepoDir $RepoDir `
    -QtInstall $QtInstall `
    -VcpkgRoot $VcpkgRoot `
    -BuildType $BuildType `
    -Clean:$Clean `
    -Jobs $Jobs

if ($LASTEXITCODE -ne 0) {
    Fail "Base build failed."
}

$upx = Get-Command upx -ErrorAction SilentlyContinue
if (-not $upx) {
    Fail "UPX is not available in PATH."
}

$exe = "$RepoDir\build\target\bin\rpgmtranslate.exe"
if (-not (Test-Path $exe)) {
    Fail "Executable not found for UPX compression: $exe"
}

$backup = "$exe.unpacked"
Copy-Item -LiteralPath $exe -Destination $backup -Force

Write-Host "Compressing executable with UPX..." -ForegroundColor Cyan
& $upx.Source @UpxArgs $exe
if ($LASTEXITCODE -ne 0) {
    Copy-Item -LiteralPath $backup -Destination $exe -Force
    Fail "UPX compression failed. Restored executable from backup."
}

& $upx.Source -t $exe
if ($LASTEXITCODE -ne 0) {
    Copy-Item -LiteralPath $backup -Destination $exe -Force
    Fail "UPX test failed. Restored executable from backup."
}

$sizeMb = [math]::Round((Get-Item $exe).Length / 1MB, 2)
Write-Host "UPX compression succeeded." -ForegroundColor Green
Write-Host "Executable: $exe" -ForegroundColor White
Write-Host "Backup:     $backup" -ForegroundColor White
Write-Host "Size:       $sizeMb MB" -ForegroundColor White