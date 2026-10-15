$ErrorActionPreference = 'Stop'
$repo = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$core = Get-Content -LiteralPath (Join-Path $repo 'payload/MayaQuadDraw_Max2024/runtime/MayaQuadDraw_Core.ms') -Raw
$native = Get-Content -LiteralPath (Join-Path $repo 'source/native/MayaQuadDrawNativeBridgeV15/MayaQuadDrawNativeBridgeV15.cpp') -Raw
$checks = 0
function Confirm([string]$label, [bool]$condition) {
    if (!$condition) { throw "Settings Tab check failed: $label" }
    $script:checks++
}
$tab = $core.Substring($core.IndexOf('fn onSettingsTab token'), $core.IndexOf('fn onHostDeferred token')-$core.IndexOf('fn onSettingsTab token'))
Confirm 'Tab callback validates active generation and pending changes' ($tab.Contains('not active or token != sessionToken or exitInProgress or historyPending or contextPending'))
Confirm 'Tab callback validates actual drawing ownership' ($tab.Contains('hasSessionContext()') -and $tab.Contains('ownsNativeCommand()') -and $tab.Contains('PBTrackGetToolActive()'))
Confirm 'Tab callback respects drags and host history' ($tab.Contains('moveGestureActive or borderGestureActive or relaxGestureActive') -and $tab.Contains('theHold.Holding() or theHold.IsSuspended() or theHold.RestoreOrRedoing()'))
Confirm 'UI-only reuse' ($tab.Contains('MayaQuadDrawUI_Toggle()') -and !($tab -match 'fileIn|PolyBoost|polyOp|PBEndTrack|\.start\(|\.stop'))
Confirm 'Other deferred events win over UI request' ($core.Contains('settingsRequested = flags == 4 and not historyPending and not contextPending'))
Confirm 'Hook stays on current Max UI thread' ($native.Contains('viewportThread != 0 && viewportThread == GetCurrentThreadId()') -and $native.Contains('SetWindowsHookExW(WH_GETMESSAGE, SettingsTabMessageProc, nullptr, viewportThread)'))
Confirm 'Only removed messages are consumed' ($native.Contains('code == HC_ACTION && removeFlag == PM_REMOVE'))
Confirm 'Exact viewport focus and destination required' ($native.Contains('GetFocus() == g_hookedViewport') -and $native.Contains('message->hwnd == g_hookedViewport'))
Confirm 'Modifier combinations retained' ($native.Contains('GetKeyState(VK_SHIFT) | GetKeyState(VK_CONTROL) | GetKeyState(VK_MENU)'))
Confirm 'Native callback queues instead of invoking scripts' ($native.Substring($native.IndexOf('LRESULT CALLBACK SettingsTabMessageProc'), $native.IndexOf('void RemoveSettingsTabHook')-$native.IndexOf('LRESULT CALLBACK SettingsTabMessageProc')) -notmatch 'ExecuteMAXScriptScript')
Confirm 'Hook chains on all paths' ($native.Contains('return CallNextHookEx(g_settingsTabHook, code, removeFlag, messagePtr);'))
Confirm 'Rapid presses preserve toggle parity' ($native.Contains('g_settingsTabPendingToggle = !g_settingsTabPendingToggle'))
Confirm 'Exit removes hook and latch' ($native -match '(?s)void EndSessionWatch\(\)\s*\{\s*RemoveSettingsTabHook\(\);')
Confirm 'Hook removal clears queued toggle' ($native -match '(?s)void RemoveSettingsTabHook\(\).*?UnhookWindowsHookEx.*?g_settingsTabKey.reset\(\);.*?g_settingsTabPendingToggle = false;')
Confirm 'Focus restore remains session guarded' ($native.Contains('generation == g_sessionGeneration') -and $native.Contains('SetFocus(settingsFocus);'))
Write-Output "Settings Tab static checks=$checks failures=0. Actual key/focus behavior requires Max manual acceptance."
