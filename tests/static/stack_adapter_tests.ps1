$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$runtime = Join-Path $repo 'payload/MayaQuadDraw_Max2024/runtime'
$checks = 0
function Confirm([string]$label, [bool]$condition) {
    if (!$condition) { throw "Stack adapter check failed: $label" }
    $script:checks++
}
foreach ($f in Get-ChildItem -LiteralPath $runtime -Filter '*.ms') {
    $s = Get-Content -LiteralPath $f.FullName -Raw
    Confirm ($f.Name+': no evaluated-node polyOp calls') (!([regex]::IsMatch($s,'polyOp\.[A-Za-z]+\s+(?:ownerNode|nodeValue)\b(?!\.baseObject)')))
    foreach ($m in [regex]::Matches($s,'polyOp\.getVert\s+(ownerNode|nodeValue)\.baseObject\s+vertexIndex[^\r\n]*')) {
        Confirm ($f.Name+': coordinate context retained') ($m.Value.Contains('node:'+$m.Groups[1].Value))
    }
}
$core = Get-Content -LiteralPath (Join-Path $runtime 'MayaQuadDraw_Core.ms') -Raw
Confirm 'Captures stack entry' ($core.Contains('savedStackObject = if savedCommandPanelMode'))
Confirm 'Voluntary exit has a guarded stack restoration' ($core.Contains('modPanel.setCurrentObject savedStackObject node:ownerNode') -and $core.Contains('if restoreContext do') -and $core.Contains('restoreContext:restoreOwnedContext'))
Confirm 'Edits base object' ($core.Contains('modPanel.setCurrentObject ownerNode.baseObject node:ownerNode'))
Confirm 'Restores native end-result state' ($core.Contains('showEndResult = savedShowEndResult'))
Confirm 'Suppresses final-mesh node ticks when stacked' ($core.Contains('ownerNode.vertexTicks = (ownerNode.modifiers.count == 0)'))
Confirm 'Checks loaded native bridge identity' ($core.Contains('v16VersionFn() == "0.17.8-max2024-v16-session-lifecycle"'))
Confirm 'Checks loaded Relax adapter identity' ($core.Contains('internalRelaxVersionFn() == "0.20.1-max2024-sdk-paint-deform-base-object"'))
foreach ($relative in @('source/native/MayaQuadDrawNativeBridgeV15/MayaQuadDrawNativeBridgeV15.cpp','source/native/MayaQuadDrawInternalRelaxV20/MayaQuadDrawInternalRelaxV20.cpp')) {
    $s = Get-Content -LiteralPath (Join-Path $repo $relative) -Raw
    Confirm ($relative+': native base resolver') ($s.Contains('object = object != nullptr ? object->FindBaseObject() : nullptr;'))
}
Write-Output "Stack adapter static checks=$checks failures=0. This verifies routing, not native interaction or crash freedom."
