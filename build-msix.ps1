<#
.SYNOPSIS
  Compila Typedown a un paquete MSIX (x64, Release) en local.

.DESCRIPTION
  Reproduce el build del CI en una maquina Windows moderna. Requiere:
    - VS 2022 Build Tools con workloads ManagedDesktop + Universal + MSIX Packaging
    - .NET Core 3.1 SDK
    - Windows SDK 10.0.18362 y 10.0.22000
    - Node + Yarn (para el editor; ver paso previo en BUILD-MSIX.md)

  Detalles y motivacion de cada flag en BUILD-MSIX.md.
#>
[CmdletBinding()]
param(
    [string]$Configuration = "Release",
    [string]$Platform = "x64"
)

$ErrorActionPreference = "Stop"
$repo = $PSScriptRoot

# --- Localizar MSBuild via vswhere ---
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere no encontrado; instala VS Build Tools 2022." }
$msb = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild `
        -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
if (-not $msb) { throw "MSBuild.exe no encontrado." }
Write-Host "MSBuild: $msb"

# Necesario para que se importen los targets UWP XAML (v17.0)
$env:VisualStudioVersion = "17.0"

$wap = Join-Path $repo "Tools\Typedown.Package\Typedown.Package.wapproj"
$app = Join-Path $repo "Dev\Typedown\Typedown.csproj"

$common = @(
    "-p:Configuration=$Configuration",
    "-p:Platform=$Platform",
    "-p:VisualStudioVersion=17.0"
)

Write-Host "`n=== [1/3] Restore (.wapproj) ==="
& $msb $wap -t:Restore @common -v:m
if ($LASTEXITCODE -ne 0) { throw "Fallo el restore del .wapproj" }

Write-Host "`n=== [2/3] Restore (Typedown.csproj, RID $Platform) ==="
& $msb $app -t:Restore @common -v:m
if ($LASTEXITCODE -ne 0) { throw "Fallo el restore de Typedown.csproj" }

Write-Host "`n=== [3/3] Build + Package -> MSIX ==="
& $msb $wap -t:Rebuild @common `
    -p:VCRTForwarders-IncludeDebugCRT=false `
    -p:UapAppxPackageBuildMode=StoreUpload `
    -p:AppxBundle=Never `
    -p:AppxPackageSigningEnabled=false `
    -m -v:m -clp:Summary
if ($LASTEXITCODE -ne 0) { throw "Fallo el empaquetado MSIX" }

$msix = Get-ChildItem (Join-Path $repo "Tools\Typedown.Package\AppPackages") `
        -Recurse -Filter *.msix -ErrorAction SilentlyContinue | Select-Object -First 1
if ($msix) {
    Write-Host "`nMSIX generado: $($msix.FullName) ($([math]::Round($msix.Length/1MB,2)) MB)" -ForegroundColor Green
} else {
    throw "No se encontro el .msix tras el build."
}
