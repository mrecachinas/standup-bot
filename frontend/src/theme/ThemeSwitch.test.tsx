import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { ThemeRoot } from "./ThemeRoot";
import { ThemeSwitch } from "./ThemeSwitch";

function renderSwitch() {
  return render(
    <ThemeRoot>
      <ThemeSwitch />
    </ThemeRoot>,
  );
}

function themeWrapper(container: HTMLElement) {
  return container.querySelector('[data-component="ThemeProvider"]');
}

async function choose(label: string) {
  const user = userEvent.setup();
  await user.click(screen.getByRole("button", { name: /^Theme:/ }));
  await user.click(await screen.findByRole("menuitemradio", { name: label }));
}

describe("ThemeSwitch", () => {
  it("defaults to syncing with the system", () => {
    const { container } = renderSwitch();
    expect(screen.getByRole("button", { name: "Theme: Sync with system" })).toBeInTheDocument();
    expect(themeWrapper(container)).toHaveAttribute("data-color-mode", "auto");
    expect(document.documentElement.dataset.colorMode).toBe("auto");
  });

  it("marks the current choice in the menu", async () => {
    const user = userEvent.setup();
    renderSwitch();

    await user.click(screen.getByRole("button", { name: /^Theme:/ }));

    expect(await screen.findByRole("menuitemradio", { name: "Sync with system" })).toHaveAttribute("aria-checked", "true");
    expect(screen.getByRole("menuitemradio", { name: "Dark" })).toHaveAttribute("aria-checked", "false");
  });

  it("persists the choice in localStorage and applies it", async () => {
    const { container } = renderSwitch();

    await choose("Dark");
    expect(window.localStorage.getItem("theme")).toBe("dark");
    expect(screen.getByRole("button", { name: "Theme: Dark" })).toBeInTheDocument();
    expect(themeWrapper(container)).toHaveAttribute("data-color-mode", "dark");
    expect(document.documentElement.dataset.colorMode).toBe("dark");

    await choose("Light");
    expect(window.localStorage.getItem("theme")).toBe("light");
    expect(themeWrapper(container)).toHaveAttribute("data-color-mode", "light");
  });

  it("restores a stored preference", () => {
    window.localStorage.setItem("theme", "light");
    const { container } = renderSwitch();
    expect(screen.getByRole("button", { name: "Theme: Light" })).toBeInTheDocument();
    expect(themeWrapper(container)).toHaveAttribute("data-color-mode", "light");
  });
});
