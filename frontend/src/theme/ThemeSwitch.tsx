import { SegmentedControl } from "@primer/react";
import { DeviceDesktopIcon, MoonIcon, SunIcon } from "@primer/octicons-react";
import { useThemePreference, type ThemePreference } from "./context";

const OPTIONS: { value: ThemePreference; label: string; icon: typeof SunIcon }[] = [
  { value: "system", label: "Auto", icon: DeviceDesktopIcon },
  { value: "light", label: "Light", icon: SunIcon },
  { value: "dark", label: "Dark", icon: MoonIcon },
];

export function ThemeSwitch() {
  const { preference, setPreference } = useThemePreference();

  return (
    <SegmentedControl aria-label="Theme" size="small" fullWidth onChange={(index) => setPreference(OPTIONS[index].value)}>
      {OPTIONS.map((option) => (
        <SegmentedControl.Button key={option.value} leadingVisual={option.icon} selected={preference === option.value}>
          {option.label}
        </SegmentedControl.Button>
      ))}
    </SegmentedControl>
  );
}
