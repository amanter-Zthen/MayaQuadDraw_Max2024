#pragma once

namespace mqd
{
    enum class SettingsTabAction { Pass, Consume, Toggle };

    // One action per physical press. Only the owned drawing viewport supplies
    // inScope=true; parameter fields and other Max windows keep normal Tab.
    struct SettingsTabKeyState
    {
        bool claimed = false;

        void reset() { claimed = false; }

        SettingsTabAction process(bool keyDown, bool keyUp, bool repeat,
                                  bool inScope, bool bareTab, bool busy)
        {
            if (keyUp)
            {
                const bool consume = claimed && inScope;
                reset();
                return consume ? SettingsTabAction::Consume : SettingsTabAction::Pass;
            }
            if (!keyDown) return SettingsTabAction::Pass;
            if (repeat)
                return claimed && inScope ? SettingsTabAction::Consume : SettingsTabAction::Pass;

            claimed = inScope && bareTab;
            if (!claimed) return SettingsTabAction::Pass;
            // Keep an in-flight drag intact; a new press after release toggles.
            return busy ? SettingsTabAction::Consume : SettingsTabAction::Toggle;
        }
    };
}
