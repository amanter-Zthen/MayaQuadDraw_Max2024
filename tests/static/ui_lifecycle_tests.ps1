$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$core = Get-Content -LiteralPath (Join-Path $repo 'payload/MayaQuadDraw_Max2024/runtime/MayaQuadDraw_Core.ms') -Raw
$startup = Get-Content -LiteralPath (Join-Path $repo 'startup/MayaQuadDraw_Max2024_Startup.ms') -Raw
$macro = Get-Content -LiteralPath (Join-Path $repo 'macro/MayaQuadDraw_Max2024.mcr') -Raw
$checks = 0
function Confirm([string]$label, [bool]$condition) {
    if (!$condition) { throw "UI static check failed: $label" }
    $script:checks++
}
$stateOffset = $core.IndexOf('struct MayaQuadDrawR6State')
Confirm 'Core state exists' ($stateOffset -gt 0)
Confirm 'Modeling lifecycle never opens UI' (!$core.Substring($stateOffset).Contains('MayaQuadDrawUI_Open('))
Confirm 'Modeling exit preserves explicit settings window' (!$core.Substring($stateOffset).Contains('MayaQuadDrawUI_Close()') -and !$startup.Contains('MayaQuadDrawUI_Close()'))
Confirm 'Open state comes from live floater' ($core.Contains('MayaQuadDrawUIFloater.open'))
Confirm 'Position reads are numeric' ($core.Contains('[xText as integer,yText as integer]'))
Confirm 'Position file is MQD-specific' ($core.Contains('MayaQuadDraw_Max2024_UI.ini'))
Confirm 'Position tracks window movement' ($core.Contains('on MayaQuadDrawUIRollout moved positionValue'))
Confirm 'Close clears stale handle' ($core -match '(?s)on MayaQuadDrawUIRollout close do.*?MayaQuadDrawUIFloater = undefined')
Confirm 'New window receives host-verified coordinates' ($core.Contains('(windowPos.x as integer) (windowPos.y as integer)'))
Confirm 'No forced floating or docking' (!$core.Contains('cui.RegisterDialogBar') -and !$core.Contains('cui.FloatDialogBar'))
Confirm 'Settings action exists' ($macro.Contains('macroScript MayaQuadDrawMax2024Settings'))
Confirm 'Settings action has correct global scope' ($macro.Contains('global MayaQuadDraw_Settings'))
Confirm 'Settings loader does not launch modeling' ($startup -match '(?s)fn MayaQuadDraw_Settings =\s*\(\s*global MayaQuadDrawUI_Toggle\s*if MayaQuadDraw_Load\(\) then MayaQuadDrawUI_Toggle\(\) else false\s*\)')
$runtimeVersion = [regex]::Match($core, 'MayaQuadDrawInstalledRuntimeVersion = "([^"]+)"').Groups[1].Value
Confirm 'Startup and Core identity match' ($runtimeVersion -ne '' -and $startup.Contains('== "'+$runtimeVersion+'"'))
Write-Output "UI static checks=$checks failures=0. Max runtime UI behavior still requires the manual UI self-test."
