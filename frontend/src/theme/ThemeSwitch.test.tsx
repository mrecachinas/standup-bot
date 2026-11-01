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

describe("ThemeSwitch", () => {
  it("defaults to Auto (system)", () => {
    const { container } = renderSwitch();
    expect(screen.getByRole("button", { name: /auto/i })).toHaveAttribute("aria-pressed", "true");
    expect(themeWrapper(container)).toHaveAttribute("data-color-mode", "auto");
    expect(document.documentElement.dataset.colorMode).toBe("auto");
  });

  it("persists the choice in localStorage and applies it", async () => {
    const user = userEvent.setup();
    const { container } = renderSwitch();

    await user.click(screen.getByRole("button", { name: /dark/i }));

    expect(window.localStorage.getItem("theme")).toBe("dark");
    expect(screen.getByRole("button", { name: /dark/i })).toHaveAttribute("aria-pressed", "true");
    expect(themeWrapper(container)).toHaveAttribute("data-color-mode", "dark");
    expect(document.documentElement.dataset.colorMode).toBe("dark");

    await user.click(screen.getByRole("button", { name: /light/i }));
    expect(window.localStorage.getItem("theme")).toBe("light");
    expect(themeWrapper(container)).toHaveAttribute("data-color-mode", "light");
  });

  it("restores a stored preference", () => {
    window.localStorage.setItem("theme", "light");
    const { container } = renderSwitch();
    expect(screen.getByRole("button", { name: /light/i })).toHaveAttribute("aria-pressed", "true");
    expect(themeWrapper(container)).toHaveAttribute("data-color-mode", "light");
  });
});
