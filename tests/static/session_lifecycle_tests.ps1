$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$core = Get-Content -LiteralPath (Join-Path $repo 'payload/MayaQuadDraw_Max2024/runtime/MayaQuadDraw_Core.ms') -Raw
$startup = Get-Content -LiteralPath (Join-Path $repo 'startup/MayaQuadDraw_Max2024_Startup.ms') -Raw
$checks = 0
function Confirm([string]$label, [bool]$condition) {
    if (!$condition) { throw "Session lifecycle check failed: $label" }
    $script:checks++
}
Confirm 'Abort is forward-declared before routes' ($core.Contains('fn abortSession eventValue shiftValue ctrlValue altValue = false') -and $core.IndexOf('fn abortSession eventValue shiftValue ctrlValue altValue = false') -lt $core.IndexOf('fn handleBuild'))
Confirm 'Relax finish is forward-declared' ($core.Contains('fn finishRelaxGesture cancelValue reasonText = false') -and $core.IndexOf('fn finishRelaxGesture cancelValue reasonText = false') -lt $core.IndexOf('fn performRelaxStep'))
Confirm 'Painter resume is forward-declared' ($core.Contains('fn resumeAfterPainter = false') -and $core.IndexOf('fn resumeAfterPainter = false') -lt $core.IndexOf('fn activatePainterRelax'))
Confirm 'Manual stop is forward-declared' ($core.Contains('fn stopManual = false') -and $core.IndexOf('fn stopManual = false') -lt $core.LastIndexOf('fn resumeAfterPainter ='))
Confirm 'Counts distinguish unsupported base types' ($core.Contains('if classOf base != Editable_Poly then'))
Confirm 'Counts tolerate host query failure' ($core.Contains('V=<unavailable> E=<unavailable> F=<unavailable>'))
$exitStart = $core.LastIndexOf('fn completeExit reasonText')
$exitEnd = $core.IndexOf('fn abortSession eventValue', $exitStart)
$exitBody = $core.Substring($exitStart,$exitEnd-$exitStart)
Confirm 'Exit detaches activity before diagnostics' ($exitBody.IndexOf('active = false') -lt $exitBody.IndexOf('local beforeExitCounts'))
Confirm 'Repeated inactive exit owns no native command' ($exitBody.Contains('if not ownedSession do return lastExitSucceeded'))
Confirm 'Exit reports result' ($exitBody.Contains('lastExitSucceeded = localStateStopped and nativeStopped and lastExitErrors.count == 0'))
Confirm 'Public stop propagates result' ($core.Contains('then MayaQuadDrawR6.stopManual() else true'))
Confirm 'Loader stop propagates result' ($startup.Contains('stopped = (MayaQuadDrawR6_Stop() == true)'))
Confirm 'No swallowed unconditional stop success' (!$startup.Contains('try (if MayaQuadDrawR6_Stop != undefined do MayaQuadDrawR6_Stop()) catch()'))
Confirm 'Passive exit preserves current context' ($core.Contains('completeExit "host context changed" endNativeTrack:ownsMode restoreContext:false'))
Confirm 'Same base object identity is required' ($core.Contains('ownerNode.baseObject == sessionBaseObject'))
Confirm 'Undo invalidates without reopening' ($core.Contains('invalidateRecognition "Host Undo/Redo settled"') -and !$core.Contains('max redo; MayaQuadDraw_Start'))
Confirm 'Callbacks are owned and nonpersistent' ($core.Contains('callbacks.removeScripts id:#MayaQuadDrawSessionLifecycle') -and $core.Contains('persistent:false'))
Confirm 'Deferred callbacks check generation' ($core.Contains('if not active or token != sessionToken or exitInProgress do return false'))
$native=Get-Content -LiteralPath (Join-Path $repo 'source/native/MayaQuadDrawNativeBridgeV15/MayaQuadDrawNativeBridgeV15.cpp') -Raw
Confirm 'Native observer uses SDK command notification' ($native.Contains('public CommandModeChangedCallback') -and $native.Contains('UnRegisterCommandModeChangedCallback'))
Confirm 'Old delayed stop checks command and generation' ($native.Contains('g_stopGeneration != g_sessionGeneration') -and $native.Contains('GetCOREInterface()->GetCommandMode() != g_stopCommand'))
Confirm 'Native delayed stop does not issue ToolToggle' (!$native.Contains('PolyBoost.ToolToggle'))
Confirm 'Native GUP shutdown clears owned observer' ($native.Contains('void Stop() override { EndSessionWatch(); RemovePressHook(); }'))
Write-Output "Session lifecycle static checks=$checks failures=0. Host state and event order require the Max regression tests."
