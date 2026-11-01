import { ActionList, ActionMenu, IconButton } from "@primer/react";
import { DeviceDesktopIcon, MoonIcon, SunIcon } from "@primer/octicons-react";
import { useThemePreference, type ThemePreference } from "./context";

const OPTIONS: { value: ThemePreference; label: string; icon: typeof SunIcon }[] = [
  { value: "system", label: "Sync with system", icon: DeviceDesktopIcon },
  { value: "light", label: "Light", icon: SunIcon },
  { value: "dark", label: "Dark", icon: MoonIcon },
];

/** An icon button showing the current theme, with a menu to change it. */
export function ThemeSwitch() {
  const { preference, setPreference } = useThemePreference();
  const current = OPTIONS.find((option) => option.value === preference) ?? OPTIONS[0];

  return (
    <ActionMenu>
      <ActionMenu.Anchor>
        <IconButton icon={current.icon} aria-label={`Theme: ${current.label}`} variant="invisible" size="small" />
      </ActionMenu.Anchor>
      <ActionMenu.Overlay width="auto">
        <ActionList selectionVariant="single" aria-label="Theme">
          {OPTIONS.map((option) => (
            <ActionList.Item key={option.value} selected={preference === option.value} onSelect={() => setPreference(option.value)}>
              <ActionList.LeadingVisual>
                <option.icon />
              </ActionList.LeadingVisual>
              {option.label}
            </ActionList.Item>
          ))}
        </ActionList>
      </ActionMenu.Overlay>
    </ActionMenu>
  );
}
