$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
$version = (Get-Content -LiteralPath (Join-Path $repo 'VERSION') -Raw).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'VERSION must contain X.Y.Z.' }
$required = @('README.md','LICENSE','LICENSE.zh-CN.txt','CONTRIBUTING.md','CHANGELOG.md','THIRD_PARTY_NOTICES.md','VERSION','mzp.run','Install_MayaQuadDraw_Max2024.ms','Uninstall_MayaQuadDraw_Max2024.ms','macro/MayaQuadDraw_Max2024.mcr','startup/MayaQuadDraw_Max2024_Startup.ms','docs/INSTALL.md','docs/BUILD.md','docs/TESTING.md','payload/MayaQuadDraw_Max2024/runtime/MayaQuadDraw_Core.ms','payload/MayaQuadDraw_Max2024/runtime/MayaQuadDraw_CandidatePreview.ms','payload/MayaQuadDraw_Max2024/runtime/MayaQuadDraw_Recognizer.ms','payload/MayaQuadDraw_Max2024/plugins/MayaQuadDrawNativeBridge_v16.dlx','payload/MayaQuadDraw_Max2024/plugins/MayaQuadDrawInternalRelax_v20.dlx','source/native/MayaQuadDrawNativeBridgeV15/MayaQuadDrawNativeBridgeV15.cpp','source/native/MayaQuadDrawNativeBridgeV16/MayaQuadDrawNativeBridgeV16.cpp','source/native/MayaQuadDrawNativeBridgeV16/StepBuildCandidateRules.h','source/native/MayaQuadDrawNativeBridgeV16/VisibilityDepthMath.h','source/native/MayaQuadDrawInternalRelaxV20/MayaQuadDrawInternalRelaxV20.cpp','tests/max/MQD_SelfTest.ms','tests/native/stepbuild_candidate_tests.cpp','tests/native/visibility_depth_tests.cpp')
foreach ($relative in $required) { if (!(Test-Path -LiteralPath (Join-Path $repo $relative) -PathType Leaf)) { throw "Missing: $relative" } }
$installer = Get-Content -LiteralPath (Join-Path $repo 'Install_MayaQuadDraw_Max2024.ms') -Raw
if (!$installer.Contains('MayaQuadDrawNativeBridge_v16.dlx') -or $installer.Contains('MayaQuadDrawNativeBridge_v15.dlx')) { throw 'Installer bridge identity mismatch.' }
$macro = Get-Content -LiteralPath (Join-Path $repo 'macro/MayaQuadDraw_Max2024.mcr') -Raw
if (!$macro.Contains('global MayaQuadDraw_Toggle')) { throw 'Macro scope fix missing.' }
$core = Get-Content -LiteralPath (Join-Path $repo 'payload/MayaQuadDraw_Max2024/runtime/MayaQuadDraw_Core.ms') -Raw
if (!$core.Contains('#MQDNativeV16CommitStepBuildFace')) { throw 'Strict preview commit entry missing.' }
$native = Get-Content -LiteralPath (Join-Path $repo 'source/native/MayaQuadDrawNativeBridgeV16/MayaQuadDrawNativeBridgeV16.cpp') -Raw
if (!$native.Contains('../MayaQuadDrawNativeBridgeV15/MayaQuadDrawNativeBridgeV15.cpp')) { throw 'V16 input-source dependency changed; review package.' }
function Test-MXSBalance([string]$path) {
    $s = Get-Content -LiteralPath $path -Raw
    $stack = [Collections.Generic.Stack[char]]::new()
    $mode = 'code'
    for ($i=0; $i -lt $s.Length; $i++) {
        $c=$s[$i]; $next=if($i+1 -lt $s.Length){$s[$i+1]}else{[char]0}
        if($mode -eq 'string'){if($c -eq '\'){$i++;continue};if($c -eq '"'){$mode='code'};continue}
        if($mode -eq 'line'){if($c -eq "`n"){$mode='code'};continue}
        if($mode -eq 'block'){if($c -eq '*' -and $next -eq '/'){$i++;$mode='code'};continue}
        if($c -eq '"'){$mode='string';continue}
        if($c -eq '-' -and $next -eq '-'){$i++;$mode='line';continue}
        if($c -eq '/' -and $next -eq '*'){$i++;$mode='block';continue}
        if('([{'.Contains($c)){$stack.Push($c)}
        if(')]}'.Contains($c)){
            if(!$stack.Count -or '([{'.IndexOf($stack.Pop()) -ne ')]}'.IndexOf($c)){throw "MXS delimiter mismatch: $path"}
        }
    }
    if($stack.Count -or $mode -in @('string','block')){throw "MXS unfinished expression: $path"}
}
foreach ($relative in $required | Where-Object { $_ -match '\.(ms|mcr)$' }) { Test-MXSBalance (Join-Path $repo $relative) }
$manifest = Join-Path $repo 'SHA256SUMS.txt'
if (Test-Path -LiteralPath $manifest) {
    foreach($line in Get-Content -LiteralPath $manifest) {
        if($line -match '^([A-Fa-f0-9]{64})  (.+)$') {
            $expected=$Matches[1]; $relative=$Matches[2]
            $path=[IO.Path]::GetFullPath((Join-Path $repo $relative))
            if(!$path.StartsWith($repo+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Manifest path outside repository.'}
            if((Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected){throw "Checksum mismatch: $relative"}
        } elseif($line.Trim()){throw 'Invalid checksum line.'}
    }
}
Write-Output "Package structure and static checks passed for $version. This does not run Max or install the plugin."
