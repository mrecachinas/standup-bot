import { createContext, useContext } from "react";

export type ThemePreference = "system" | "light" | "dark";
export type PrimerColorMode = "auto" | "day" | "night";

export const THEME_STORAGE_KEY = "theme";

export const COLOR_MODES: Record<ThemePreference, PrimerColorMode> = {
  system: "auto",
  light: "day",
  dark: "night",
};

export function readThemePreference(): ThemePreference {
  try {
    const stored = window.localStorage.getItem(THEME_STORAGE_KEY);
    if (stored === "light" || stored === "dark" || stored === "system") return stored;
  } catch {
    // Storage can be unavailable (privacy mode); fall back to the system theme.
  }
  return "system";
}

export function writeThemePreference(preference: ThemePreference): void {
  try {
    window.localStorage.setItem(THEME_STORAGE_KEY, preference);
  } catch {
    // Ignore: the choice still applies for this page view.
  }
}

export interface ThemeValue {
  preference: ThemePreference;
  setPreference: (preference: ThemePreference) => void;
}

export const ThemeContext = createContext<ThemeValue>({
  preference: "system",
  setPreference: () => {},
});

export function useThemePreference(): ThemeValue {
  return useContext(ThemeContext);
}
