param(
    [string]$MaxSDK = 'C:\Program Files\Autodesk\3ds Max 2024 SDK\maxsdk',
    [string]$MSBuild,
    [switch]$StageBinaries
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (!$MSBuild) {
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path -LiteralPath $vswhere) {
        $MSBuild = & $vswhere -latest -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
    }
}
if (!$MSBuild -or !(Test-Path -LiteralPath $MSBuild)) { throw 'Specify a valid MSBuild.exe path.' }
if (!(Test-Path -LiteralPath (Join-Path $MaxSDK 'ProjectSettings\PropertySheets\3dsmax.cpp.props'))) { throw '3ds Max 2024 SDK not found.' }
$projects = @(
    @('MayaQuadDrawNativeBridgeV16','MayaQuadDrawNativeBridge_v16.dlx'),
    @('MayaQuadDrawInternalRelaxV20','MayaQuadDrawInternalRelax_v20.dlx')
)
foreach ($entry in $projects) {
    $folder = Join-Path $repo ('source\native\'+$entry[0])
    & $MSBuild (Join-Path $folder ($entry[0]+'.vcxproj')) /p:Configuration=Release /p:Platform=x64 "/p:MaxSDK=$MaxSDK" /v:minimal /nologo
    if ($LASTEXITCODE -ne 0) { throw ('Build failed: '+$entry[0]) }
    if ($StageBinaries) {
        Copy-Item -LiteralPath (Join-Path $folder ('bin\Release\'+$entry[1])) -Destination (Join-Path $repo ('payload\MayaQuadDraw_Max2024\plugins\'+$entry[1])) -Force
    }
}
Write-Output 'Native builds succeeded. No installed Max files were modified.'
