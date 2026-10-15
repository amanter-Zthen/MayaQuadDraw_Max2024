$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$core = Get-Content -LiteralPath (Join-Path $repo 'payload/MayaQuadDraw_Max2024/runtime/MayaQuadDraw_Core.ms') -Raw
$startup = Get-Content -LiteralPath (Join-Path $repo 'startup/MayaQuadDraw_Max2024_Startup.ms') -Raw
$checks = 0
function Confirm([string]$label, [bool]$condition) {
    if (!$condition) { throw "AutoWeld Undo static check failed: $label" }
    $script:checks++
}
$start = $core.IndexOf('fn commitAutoWeldTarget')
$end = $core.IndexOf('fn tryAutoWeld', $start)
$body = $core.Substring($start, $end-$start)
Confirm 'Explicit native undo context' ($body.Contains('undo "MQD Auto Weld" on'))
Confirm 'Foreign or suspended history is respected' ($body.Contains('beforeUndo[1] or beforeUndo[2] or beforeUndo[3] != 0 or beforeUndo[4] != 0'))
Confirm 'Restoration cannot create another weld' ($body.Contains('theHold.RestoreOrRedoing()'))
Confirm 'Weld requires actual recording' ($body.Contains('if theHold.Holding() and not theHold.IsSuspended() then'))
Confirm 'Native weld remains sole geometry kernel' ($body.Contains('polyOp.weldVerts ownerNode.baseObject movedVertex targetVertex targetWorld node:ownerNode'))
Confirm 'World/node context retained' ($body.Contains('in coordsys world'))
Confirm 'Rejected result cancels own record' ($body.Contains('if not successValue do theHold.Cancel()'))
Confirm 'Exception cancels own record' ($body.Contains('if theHold.Holding() do theHold.Cancel()'))
Confirm 'No native history override' (!$body.Contains('theHold.Resume') -and !$body.Contains('theHold.EnableUndo') -and !$body.Contains('theHold.DisableUndo'))
Confirm 'No group/whole-mesh snapshot engine' (!$body.Contains('SuperBegin') -and !$body.Contains('setVert') -and !$body.Contains('snapshotAsMesh'))
Confirm 'Target picker preserved' ($core.Contains('local targetInfo = findAutoWeldTarget movedVertex'))
$runtimeVersion = [regex]::Match($core, 'MayaQuadDrawInstalledRuntimeVersion = "([^"]+)"').Groups[1].Value
Confirm 'Two-step candidate versions agree' ($runtimeVersion -ne '' -and $startup.Contains('== "'+$runtimeVersion+'"'))
Write-Output "AutoWeld Undo static checks=$checks failures=0. Real pointer release remains a manual acceptance gate."
