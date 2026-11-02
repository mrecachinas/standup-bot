import { render, screen, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router";
import { describe, expect, it, vi } from "vitest";
import { StandupHeader } from "./StandupHeader";

const standup = {
  id: 7,
  name: "Daily standup",
  platform: "teams" as const,
  platform_label: "Microsoft Teams",
  platform_channel: "T1|19:abc@thread.tacv2",
  platform_channel_name: "Engineering › General",
  active: true,
  respect_timezone: true,
  schedule_summary: "Weekdays at 9:00 AM",
  active_participants_count: 3,
};

describe("StandupHeader", () => {
  it("shows the title, meta and tabs", async () => {
    const onPauseResume = vi.fn();
    render(
      <MemoryRouter>
        <StandupHeader standup={standup} active="participants" onPauseResume={onPauseResume} />
      </MemoryRouter>,
    );

    expect(screen.getByRole("heading", { level: 1, name: "Daily standup" })).toBeInTheDocument();
    expect(screen.getByText("Active")).toBeInTheDocument();
    expect(screen.getByText("Engineering › General")).toBeInTheDocument();
    expect(screen.getByText("Weekdays at 9:00 AM")).toBeInTheDocument();
    expect(screen.getByText("3 people")).toBeInTheDocument();
    expect(screen.getByText("Participant timezones")).toBeInTheDocument();
    // The Settings tab is the way in, so there's no separate "Edit standup" button.
    expect(screen.queryByRole("link", { name: /Edit standup/ })).toBeNull();

    const tabs = screen.getByRole("navigation", { name: "Daily standup sections" });
    expect(within(tabs).getAllByRole("link").map((link) => link.textContent?.replace(/\d.*$/, ""))).toEqual(["Overview", "Insights", "Responses", "People", "Settings"]);
    expect(within(tabs).getByRole("link", { name: /People/ })).toHaveAttribute("aria-current", "page");
    expect(within(tabs).getByRole("link", { name: /Insights/ })).toHaveAttribute("href", "/manager/standups/7/analytics");
    expect(within(tabs).getByRole("link", { name: /Settings/ })).toHaveAttribute("href", "/manager/standups/7/edit");

    await userEvent.click(screen.getByRole("button", { name: "Pause Daily standup" }));
    expect(onPauseResume).toHaveBeenCalled();
  });
});
