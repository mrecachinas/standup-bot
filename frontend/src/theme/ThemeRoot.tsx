import { useCallback, useEffect, useMemo, useState, type ReactNode } from "react";
import { BaseStyles } from "@primer/react";
import { ThemeProvider } from "@primer/react/next";
import { COLOR_MODES, ThemeContext, readThemePreference, writeThemePreference, type ThemePreference } from "./context";

const DOCUMENT_MODES: Record<ThemePreference, string> = { system: "auto", light: "light", dark: "dark" };

/** Primer theme + BaseStyles, with the Auto/Light/Dark choice kept in localStorage. */
export function ThemeRoot({ children }: { children: ReactNode }) {
  const [preference, setPreferenceState] = useState<ThemePreference>(readThemePreference);

  const setPreference = useCallback((next: ThemePreference) => {
    writeThemePreference(next);
    setPreferenceState(next);
  }, []);

  // The page background lives outside the ThemeProvider's wrapper, so mirror
  // the mode onto <html> for the primitives' [data-color-mode] selectors.
  useEffect(() => {
    const root = document.documentElement;
    root.dataset.colorMode = DOCUMENT_MODES[preference];
    root.dataset.lightTheme = "light";
    root.dataset.darkTheme = "dark";
  }, [preference]);

  const value = useMemo(() => ({ preference, setPreference }), [preference, setPreference]);

  return (
    <ThemeContext.Provider value={value}>
      <ThemeProvider colorMode={COLOR_MODES[preference]} dayScheme="light" nightScheme="dark">
        <BaseStyles>{children}</BaseStyles>
      </ThemeProvider>
    </ThemeContext.Provider>
  );
}
