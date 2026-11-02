import { render, screen, within } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { describe, expect, it } from "vitest";
import { standupFixture } from "../test/fixtures";
import { StandupHeader } from "./StandupHeader";

const standup = standupFixture({
  platform: "teams",
  platform_label: "Microsoft Teams",
  platform_channel: "T1|19:abc@thread.tacv2",
  platform_channel_name: "Engineering › General",
  channel_label: "Engineering › General",
  active_participants_count: 3,
});

describe("StandupHeader", () => {
  it("shows the title, meta and tabs", () => {
    render(
      <MemoryRouter>
        <StandupHeader standup={standup} active="participants" />
      </MemoryRouter>,
    );

    expect(screen.getByRole("heading", { level: 1, name: "Daily standup" })).toBeInTheDocument();
    expect(screen.getByText("Active")).toBeInTheDocument();
    expect(screen.getByText("Engineering › General")).toBeInTheDocument();
    expect(screen.getByText("Weekdays at 9:30 AM")).toBeInTheDocument();
    expect(screen.getByText("3 participants")).toBeInTheDocument();
    expect(screen.getByText("Participant timezones")).toBeInTheDocument();
    expect(screen.getByRole("link", { name: /Edit standup/ })).toHaveAttribute("href", "/manager/standups/7/edit");

    const tabs = screen.getByRole("navigation", { name: "Daily standup sections" });
    expect(within(tabs).getByRole("link", { name: /Participants/ })).toHaveAttribute("aria-current", "page");
    expect(within(tabs).getByRole("link", { name: /Microsoft Teams/ })).toHaveAttribute("href", "/manager/standups/7/chat_setup");
    expect(within(tabs).getByRole("link", { name: /Insights/ })).toHaveAttribute("href", "/manager/standups/7/analytics");
    expect(screen.queryByRole("button", { name: "Pause Daily standup" })).toBeNull();
  });
});
