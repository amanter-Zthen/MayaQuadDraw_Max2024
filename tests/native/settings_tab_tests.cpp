#include "../../source/native/MayaQuadDrawNativeBridgeV15/SettingsTabPolicy.h"
#include <cstdio>
#include <cstdlib>
#include <initializer_list>

using mqd::SettingsTabAction;
using mqd::SettingsTabKeyState;
static int checks = 0;

void check(const char* label, bool okay)
{
    ++checks;
    if (!okay) { std::printf("FAIL: %s\n", label); std::exit(1); }
}

int main()
{
    for (bool scope : {false, true})
        for (bool bare : {false, true})
            for (bool busy : {false, true})
            {
                SettingsTabKeyState key;
                const auto expected = !scope || !bare ? SettingsTabAction::Pass :
                    busy ? SettingsTabAction::Consume : SettingsTabAction::Toggle;
                check("fresh Tab scope/modifiers/drag matrix",
                      key.process(true, false, false, scope, bare, busy) == expected);
                check("key-up ownership matrix", key.process(false, true, true, scope, bare, busy) ==
                      (scope && bare ? SettingsTabAction::Consume : SettingsTabAction::Pass));
                check("key-up clears ownership", !key.claimed);
            }

    SettingsTabKeyState key;
    check("press toggles", key.process(true, false, false, true, true, false) == SettingsTabAction::Toggle);
    for (int repeat = 0; repeat < 100; ++repeat)
        check("held key never toggles again", key.process(true, false, true, true, true, false) == SettingsTabAction::Consume);
    check("release consumed", key.process(false, true, true, true, true, false) == SettingsTabAction::Consume);
    check("second press toggles", key.process(true, false, false, true, true, false) == SettingsTabAction::Toggle);

    check("focus moved to a field: repeat passes", key.process(true, false, true, false, true, false) == SettingsTabAction::Pass);
    check("focus moved to a field: release passes", key.process(false, true, true, false, true, false) == SettingsTabAction::Pass);
    check("field Tab passes", key.process(true, false, false, false, true, false) == SettingsTabAction::Pass);
    check("held before entering MQD is not claimed", key.process(true, false, true, true, true, false) == SettingsTabAction::Pass);
    check("unclaimed release passes", key.process(false, true, true, true, true, false) == SettingsTabAction::Pass);
    check("drag-time press consumed", key.process(true, false, false, true, true, true) == SettingsTabAction::Consume);
    check("ending drag while Tab held does not toggle", key.process(true, false, true, true, true, false) == SettingsTabAction::Consume);
    key.process(false, true, true, true, true, false);
    check("fresh press after drag toggles", key.process(true, false, false, true, true, false) == SettingsTabAction::Toggle);
    key.reset();
    check("session exit clears latch", !key.claimed);
    check("after exit key-up passes", key.process(false, true, true, false, true, false) == SettingsTabAction::Pass);
    check("non-key event passes", key.process(false, false, false, true, true, false) == SettingsTabAction::Pass);
    std::printf("Settings Tab policy checks=%d failures=0. Physical Max routing remains a host test.\n", checks);
    return 0;
}
