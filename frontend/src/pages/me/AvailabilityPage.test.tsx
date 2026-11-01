import { fireEvent, screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { jsonResponse, memberBootstrap } from "../../test/fixtures";
import { mockFetch, renderApp } from "../../test/render";
import { availabilityPayload, memberProfile } from "./components/fixtures";

const awayPayload = () =>
  availabilityPayload({
    away: [{ participant_id: 70, standup_id: 7, standup_name: "Daily standup", vacation_until: "2026-11-06", vacation_until_label: "Friday, November 6" }],
  });

function requestsTo(fetchMock: ReturnType<typeof mockFetch>, method: string) {
  return fetchMock.mock.calls.filter(([url, init]) => url === "/api/me/availability" && init?.method === method);
}

describe("AvailabilityPage", () => {
  it("shows the form with every active standup selected", async () => {
    mockFetch(memberBootstrap(), (url) => (url === "/api/me/availability" ? jsonResponse(availabilityPayload()) : undefined));
    renderApp("/me/availability");

    expect(await screen.findByRole("heading", { level: 1, name: "Availability" })).toBeInTheDocument();
    await waitFor(() => expect(document.title).toBe("Availability · Standup Bot"));
    expect(screen.getByText("Going on vacation or out sick? Pause your check-ins so they don't count as missed.")).toBeInTheDocument();
    expect(screen.queryByRole("heading", { name: "Currently away" })).toBeNull();

    const date = screen.getByLabelText(/Last day away/);
    expect(date).toHaveAttribute("type", "date");
    expect(date).toHaveAttribute("min", "2026-11-01");
    expect(date).toHaveAttribute("max", "2027-11-01");
    expect(date).toHaveValue("");
    expect(screen.getByRole("checkbox", { name: "Daily standup" })).toBeChecked();
    expect(screen.getByRole("checkbox", { name: "Retro" })).toBeChecked();
    expect(screen.getByText(/You can also DM the bot/)).toBeInTheDocument();
  });

  it("lists where the member is away and clears it", async () => {
    const user = userEvent.setup();
    const fetchMock = mockFetch(memberBootstrap(), (url, init) => {
      if (url === "/api/me/availability" && init.method === "GET") return jsonResponse(awayPayload());
      if (url === "/api/me/availability/clear" && init.method === "DELETE") {
        return jsonResponse({ ...availabilityPayload(), notice: "Welcome back. You'll get your next check-ins as usual." });
      }
      return undefined;
    });
    renderApp("/me/availability");

    const away = await screen.findByRole("region", { name: "Currently away" });
    expect(within(away).getByText("Daily standup")).toBeInTheDocument();
    expect(within(away).getByText("through Friday, November 6")).toBeInTheDocument();

    await user.click(within(away).getByRole("button", { name: "I'm back" }));

    expect(await screen.findByText("Welcome back. You'll get your next check-ins as usual.")).toBeInTheDocument();
    await waitFor(() => expect(screen.queryByRole("region", { name: "Currently away" })).toBeNull());
    expect(fetchMock.mock.calls.filter(([url, init]) => url === "/api/me/availability/clear" && init?.method === "DELETE")).toHaveLength(1);
  });

  it("sets time away for the chosen standups", async () => {
    const user = userEvent.setup();
    const fetchMock = mockFetch(memberBootstrap(), (url, init) => {
      if (url === "/api/me/availability" && init.method === "GET") return jsonResponse(availabilityPayload());
      if (url === "/api/me/availability" && init.method === "PATCH") {
        return jsonResponse({ ...awayPayload(), notice: "You're marked away through Friday, November 6." });
      }
      return undefined;
    });
    renderApp("/me/availability");

    fireEvent.change(await screen.findByLabelText(/Last day away/), { target: { value: "2026-11-06" } });
    await user.click(screen.getByRole("checkbox", { name: "Retro" }));
    expect(screen.getByRole("checkbox", { name: "Retro" })).not.toBeChecked();
    await user.click(screen.getByRole("button", { name: "Save" }));

    expect(await screen.findByText("You're marked away through Friday, November 6.")).toBeInTheDocument();
    const [patchCall] = requestsTo(fetchMock, "PATCH");
    expect(JSON.parse(String(patchCall[1]!.body))).toEqual({ away_until: "2026-11-06", standup_ids: [7] });
    expect(await screen.findByRole("region", { name: "Currently away" })).toBeInTheDocument();
    expect(screen.getByLabelText(/Last day away/)).toHaveValue("");
    expect(screen.getByRole("checkbox", { name: "Retro" })).toBeChecked();
  });

  it("validates the date and standups before saving", async () => {
    const user = userEvent.setup();
    const fetchMock = mockFetch(memberBootstrap(), (url) => (url === "/api/me/availability" ? jsonResponse(availabilityPayload()) : undefined));
    renderApp("/me/availability");

    await user.click(await screen.findByRole("checkbox", { name: "Daily standup" }));
    await user.click(screen.getByRole("checkbox", { name: "Retro" }));
    await user.click(screen.getByRole("button", { name: "Save" }));

    expect(screen.getByText("Choose the last day you'll be away.")).toBeInTheDocument();
    // CheckboxGroup also repeats its validation message, visually hidden, in the legend.
    expect(screen.getAllByText("Choose at least one standup.").length).toBeGreaterThan(0);
    expect(screen.getByLabelText(/Last day away/)).toHaveAttribute("aria-invalid", "true");

    fireEvent.change(screen.getByLabelText(/Last day away/), { target: { value: "2026-10-01" } });
    expect(screen.getByText("The last day away can't be in the past.")).toBeInTheDocument();
    fireEvent.change(screen.getByLabelText(/Last day away/), { target: { value: "2028-01-01" } });
    expect(screen.getByText("You can only set time away up to a year ahead.")).toBeInTheDocument();
    expect(requestsTo(fetchMock, "PATCH")).toHaveLength(0);
  });

  it("shows the server's 422 error", async () => {
    const user = userEvent.setup();
    mockFetch(memberBootstrap(), (url, init) => {
      if (url === "/api/me/availability" && init.method === "GET") return jsonResponse(availabilityPayload());
      if (url === "/api/me/availability" && init.method === "PATCH") {
        return jsonResponse({ ...availabilityPayload(), error: "Choose at least one standup.", errors: ["Choose at least one standup."] }, 422);
      }
      return undefined;
    });
    renderApp("/me/availability");

    fireEvent.change(await screen.findByLabelText(/Last day away/), { target: { value: "2026-11-06" } });
    await user.click(screen.getByRole("button", { name: "Save" }));

    expect(await screen.findByText("Couldn't set your time away")).toBeInTheDocument();
    expect(screen.getByText("Choose at least one standup.")).toBeInTheDocument();
    expect(screen.getByLabelText(/Last day away/)).toHaveValue("2026-11-06");
  });

  it("explains when there's nothing to pause", async () => {
    mockFetch(memberBootstrap(), (url) =>
      url === "/api/me/availability" ? jsonResponse(availabilityPayload({ member: { ...memberProfile, platform_label: "Microsoft Teams" }, standups: [] })) : undefined,
    );
    renderApp("/me/availability");

    expect(await screen.findByText("You aren't active in any standups right now.")).toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Save" })).toBeNull();
  });
});
