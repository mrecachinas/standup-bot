import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import { jsonResponse, userBootstrap } from "../../test/fixtures";
import { mockFetch, renderApp } from "../../test/render";
import { reportFixture } from "./insights/testFixtures";

const PATH = "/api/standups/7/report";

function bodyOf(fetchMock: ReturnType<typeof mockFetch>, method: string, url: string) {
  const call = fetchMock.mock.calls.find(([callUrl, init]) => callUrl === url && init?.method === method);
  return call ? JSON.parse(String(call[1]!.body ?? "null")) : undefined;
}

describe("StandupReportPage", () => {
  it("renders the settings, history, send-now card and summary", async () => {
    mockFetch(userBootstrap(), (url, init) => (url === PATH && init.method === "GET" ? jsonResponse(reportFixture()) : undefined));
    renderApp("/manager/standups/7/report");

    expect(await screen.findByRole("heading", { name: "Delivery settings" })).toBeInTheDocument();
    await waitFor(() => expect(document.title).toBe("Reports · Daily standup · Standup Bot"));
    expect(within(screen.getByRole("navigation", { name: "Settings" })).getByRole("link", { name: "Reports" })).toHaveAttribute("aria-current", "page");
    expect(within(screen.getByRole("navigation", { name: "Daily standup sections" })).getByRole("link", { name: "Settings" })).toHaveAttribute("aria-current", "page");

    expect(screen.getByLabelText("Post to channel")).toHaveValue("C0123");
    expect(screen.getByLabelText("Post to channel")).toHaveAttribute("placeholder", "daily-standup or C0123");
    expect(screen.getByText("Channel name or ID, without spaces.")).toBeInTheDocument();
    expect(screen.getByLabelText("Also send to")).toHaveValue("U9");
    expect(screen.getByLabelText("Also send to")).toHaveAttribute("placeholder", "One Slack user or channel ID per line");
    expect(screen.getByText("Optional. Slack user IDs get a DM; channel IDs get a post.")).toBeInTheDocument();
    expect(screen.getByLabelText("Format")).toHaveValue("slack");
    expect(screen.getByLabelText("Detail")).toHaveValue("detailed");

    const table = screen.getByRole("table", { name: "History" });
    const rows = within(table).getAllByRole("row");
    expect(rows).toHaveLength(3);
    expect(rows[1]).toHaveTextContent("by Maya Manager");
    expect(rows[1]).toHaveTextContent("Completed");
    expect(rows[1]).toHaveTextContent("3 responses to 1 destination");
    expect(rows[2]).toHaveTextContent("Scheduled");
    expect(rows[2]).toHaveTextContent("Failed");
    expect(rows[2]).toHaveTextContent("channel_not_found");

    expect(screen.getByRole("heading", { name: "Send a report now" })).toBeInTheDocument();
    expect(screen.getByText("Builds a report from today's responses using the saved settings.")).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Last 30 days" })).toBeInTheDocument();
    expect(screen.getByText("75%")).toBeInTheDocument();
  });

  it("shows an empty history", async () => {
    mockFetch(userBootstrap(), (url) => (url === PATH ? jsonResponse(reportFixture({ report_generations: [] })) : undefined));
    renderApp("/manager/standups/7/report");

    expect(await screen.findByText("No reports have been sent yet.")).toBeInTheDocument();
    expect(screen.queryByRole("table")).toBeNull();
  });

  it("saves the delivery settings", async () => {
    const user = userEvent.setup();
    const saved = reportFixture();
    saved.report_configuration = { ...saved.report_configuration, delivery_channel: "C999", detail_level: "summary", detail_level_label: "Summary", updated_at: "2026-10-31T10:00:00Z" };
    const fetchMock = mockFetch(userBootstrap(), (url, init) => {
      if (url === PATH && init.method === "PATCH") return jsonResponse({ ...saved, notice: "Report settings saved." });
      if (url === PATH) return jsonResponse(reportFixture());
      return undefined;
    });
    renderApp("/manager/standups/7/report");

    const channel = await screen.findByLabelText("Post to channel");
    await user.clear(channel);
    await user.type(channel, " C999 ");
    await user.clear(screen.getByLabelText("Also send to"));
    await user.selectOptions(screen.getByLabelText("Format"), "markdown");
    await user.selectOptions(screen.getByLabelText("Detail"), "summary");
    await user.click(screen.getByRole("button", { name: "Save settings" }));

    expect(await screen.findByText("Report settings saved.")).toBeInTheDocument();
    expect(bodyOf(fetchMock, "PATCH", PATH)).toEqual({
      report_configuration: { delivery_channel: "C999", recipients_text: "", report_format: "markdown", detail_level: "summary" },
    });
    const sendNow = screen.getByRole("heading", { name: "Send a report now" }).closest("section")!;
    await waitFor(() => expect(within(sendNow).getByText("C999")).toBeInTheDocument());
    expect(within(sendNow).getByText("Summary")).toBeInTheDocument();
  });

  it("shows 422 field errors on the form", async () => {
    const user = userEvent.setup();
    mockFetch(userBootstrap(), (url, init) => {
      if (url === PATH && init.method === "PATCH") {
        return jsonResponse(
          {
            errors: ["Delivery channel can't be blank", "Recipients contain invalid Slack channel or user IDs: nope"],
            field_errors: { delivery_channel: ["can't be blank"], recipients: ["contain invalid Slack channel or user IDs: nope"] },
          },
          422,
        );
      }
      if (url === PATH) return jsonResponse(reportFixture());
      return undefined;
    });
    renderApp("/manager/standups/7/report");

    await user.clear(await screen.findByLabelText("Post to channel"));
    await user.click(screen.getByRole("button", { name: "Save settings" }));

    expect(await screen.findByText("Fix the report settings")).toBeInTheDocument();
    expect(screen.getByText("Delivery channel can't be blank")).toBeInTheDocument();
    expect(screen.getByText("Channel can't be blank")).toBeInTheDocument();
    expect(screen.getByLabelText("Post to channel")).toHaveAttribute("aria-invalid", "true");
    expect(screen.getByLabelText("Also send to")).toHaveAccessibleDescription("Recipients contain invalid Slack channel or user IDs: nope");
  });

  it("generates a report now", async () => {
    const user = userEvent.setup();
    const fetchMock = mockFetch(userBootstrap(), (url, init) => {
      if (url === `${PATH}/generate` && init.method === "POST") return jsonResponse({ ...reportFixture(), notice: "Report queued. It will appear in the history below when it's sent." });
      if (url === PATH) return jsonResponse(reportFixture());
      return undefined;
    });
    renderApp("/manager/standups/7/report");

    await user.click(await screen.findByRole("button", { name: "Send report now" }));

    expect(await screen.findByText("Report queued. It will appear in the history below when it's sent.")).toBeInTheDocument();
    expect(fetchMock.mock.calls.some(([url, init]) => url === `${PATH}/generate` && init?.method === "POST")).toBe(true);
  });

  it("shows why a report couldn't be generated and the updated history", async () => {
    const user = userEvent.setup();
    const failed = reportFixture();
    failed.report_generations = [{ ...failed.report_generations[1], id: 12, error_message: "No channel configured", result_label: "No channel configured", requested_by_label: "by Maya Manager" }];
    mockFetch(userBootstrap(), (url, init) => {
      if (url === `${PATH}/generate` && init.method === "POST") return jsonResponse({ ...failed, error: "No channel configured", errors: ["No channel configured"] }, 422);
      if (url === PATH) return jsonResponse(reportFixture());
      return undefined;
    });
    renderApp("/manager/standups/7/report");

    await user.click(await screen.findByRole("button", { name: "Send report now" }));

    expect(await screen.findByText("Couldn't generate the report")).toBeInTheDocument();
    const rows = within(screen.getByRole("table", { name: "History" })).getAllByRole("row");
    expect(rows).toHaveLength(2);
    expect(rows[1]).toHaveTextContent("No channel configured");
  });
});
