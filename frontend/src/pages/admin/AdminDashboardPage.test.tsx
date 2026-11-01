import { screen, waitFor, within } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it } from "vitest";
import type { AdminDashboard } from "../../api/types/admin";
import { jsonResponse, userBootstrap } from "../../test/fixtures";
import { mockFetch, renderApp } from "../../test/render";

function dashboard(overrides: Partial<AdminDashboard> = {}): AdminDashboard {
  const recent = new Date(Date.now() - 5 * 60 * 1000).toISOString();
  return {
    health: { status: "degraded", status_label: "Degraded", status_tone: "warning", checked_at: recent },
    health_checks: [
      {
        key: "database",
        label: "Database",
        icon: "database",
        status: "ok",
        status_label: "Operational",
        status_tone: "success",
        details: [
          { label: "Adapter", value: "PostgreSQL", time: null, strong: false },
          { label: "Latency", value: "2 ms", time: null, strong: false },
        ],
      },
      {
        key: "job_queue",
        label: "Job queue",
        icon: "stack",
        status: "warn",
        status_label: "Degraded",
        status_tone: "warning",
        details: [
          { label: "Adapter", value: "solid_queue", time: null, strong: false },
          { label: "Pending", value: "4", time: null, strong: false },
          { label: "Failed", value: "2", time: null, strong: true },
        ],
      },
      {
        key: "slack_api",
        label: "Slack",
        icon: "hash",
        status: "ok",
        status_label: "Operational",
        status_tone: "success",
        details: [
          { label: "Bot token", value: "Configured", time: null, strong: false },
          { label: "Signing secret", value: "Configured", time: null, strong: false },
          { label: "Last message", value: null, time: recent, strong: false },
        ],
      },
      {
        key: "teams_api",
        label: "Microsoft Teams",
        icon: "people",
        status: "warn",
        status_label: "Not configured",
        status_tone: "warning",
        details: [
          { label: "App ID", value: "Missing", time: null, strong: false },
          { label: "Client secret", value: "Missing", time: null, strong: false },
          { label: "Tenant", value: "Missing", time: null, strong: false },
          { label: "Last message", value: "—", time: null, strong: false },
        ],
      },
    ],
    stats: {
      standups_total: 5,
      standups_active: 4,
      standups_paused: 1,
      active_people: 12,
      active_participants: 15,
      responses_last_24h: 9,
      completed_last_24h: 7,
      users_active: 3,
      users_admin: 1,
      standup_owners: 2,
    },
    activity_days: 14,
    daily_activity: [
      { date: "2026-10-30", expected: 5, completed: 4, skipped: 0, pending: 1, missed: 0, completion_rate: 80, label: "Oct 30", total: 5, title: "Oct 30, 2026: 4 completed, 0 skipped, 0 missed, 1 pending (80%)" },
    ],
    daily_activity_has_pending: true,
    response_totals: {
      total: 1250,
      statuses: [
        { status: "completed", label: "Completed", count: 1000, percent: 80, tone: "success" },
        { status: "expired", label: "Expired", count: 250, percent: 20, tone: "warning" },
      ],
    },
    users: [
      {
        id: 1,
        name: "Ada Admin",
        email: "ada@example.com",
        placeholder_email: false,
        subtitle: "ada@example.com",
        identities: [],
        avatar_url: null,
        admin: true,
        access_label: "Admin",
        access_tone: "accent",
        owned_standups_count: 0,
        owned_standups_label: "All",
        last_signed_in_at: recent,
        active: true,
        status_label: "Active",
        status_tone: "success",
      },
      {
        id: 2,
        name: "Sam Slack",
        email: "slack-U123@users.standup.invalid",
        placeholder_email: true,
        subtitle: "Slack U123",
        identities: [{ platform: "slack", platform_user_id: "U123" }],
        avatar_url: null,
        admin: false,
        access_label: "Member",
        access_tone: null,
        owned_standups_count: 2,
        owned_standups_label: "2",
        last_signed_in_at: null,
        active: false,
        status_label: "Disabled",
        status_tone: null,
      },
    ],
    audit_logs: [
      {
        id: 50,
        action: "standup.update",
        action_label: "standup update",
        actor_name: "Ada Admin",
        actor_avatar_url: null,
        auditable_type: "Standup",
        auditable_label: "Standup #7",
        auditable_id: 7,
        created_at: recent,
      },
    ],
    failed_reports: [{ id: 9, standup_id: 7, standup_name: "Daily standup", error_message: "channel_not_found", requested_at: recent }],
    ...overrides,
  };
}

describe("AdminDashboardPage", () => {
  it("renders health, stats, activity, users, changes and failed reports", async () => {
    mockFetch(userBootstrap({ admin: true }), (url) => (url === "/api/admin/dashboard" ? jsonResponse(dashboard()) : undefined));
    renderApp("/admin");

    expect(await screen.findByRole("heading", { name: "Job queue" })).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "Admin", level: 1 })).toBeInTheDocument();
    expect(document.title).toBe("Admin · Standup Bot");
    expect(screen.getByText(/Installation health, usage, and recent changes\. Checked/)).toHaveTextContent("Checked 5 minutes ago.");

    const queue = screen.getByRole("region", { name: "Job queue" });
    expect(queue).toHaveTextContent("Degraded");
    expect(queue).toHaveTextContent("Pending4");
    const slack = screen.getByRole("region", { name: "Slack" });
    expect(slack).toHaveTextContent("Last message5 minutes ago");
    expect(screen.getByRole("region", { name: "Microsoft Teams" })).toHaveTextContent("Not configured");

    expect(screen.getByText("4 active · 1 paused")).toBeInTheDocument();
    expect(screen.getByText("15 active memberships across standups")).toBeInTheDocument();
    expect(screen.getByText("7 completed")).toBeInTheDocument();
    expect(screen.getByText("1 admin · 2 running standups")).toBeInTheDocument();

    expect(screen.getByText("Last 14 days, all standups")).toBeInTheDocument();
    expect(screen.getByRole("img", { name: "Responses per day across the installation" })).toBeInTheDocument();
    expect(screen.getByRole("region", { name: "Response activity" })).toHaveTextContent("Pending");
    expect(screen.getByText("1,000")).toBeInTheDocument();
    expect(screen.getByRole("progressbar", { name: "Expired responses" })).toHaveAttribute("aria-valuenow", "20");

    const users = screen.getByRole("table", { name: "Users" });
    const rows = within(users).getAllByRole("row");
    expect(rows).toHaveLength(3);
    expect(rows[1]).toHaveTextContent("Ada Admin");
    expect(rows[1]).toHaveTextContent("All");
    expect(rows[2]).toHaveTextContent("Slack U123");
    expect(rows[2]).toHaveTextContent("Member");
    expect(rows[2]).toHaveTextContent("Disabled");

    const changes = screen.getByRole("list", { name: "Recent changes" });
    expect(changes).toHaveTextContent("Ada Admin standup update");
    expect(changes).toHaveTextContent("Standup #7");

    const failed = screen.getByRole("list", { name: "Failed reports" });
    expect(within(failed).getByRole("link", { name: "Daily standup" })).toHaveAttribute("href", "/manager/standups/7/report");
    expect(failed).toHaveTextContent("channel_not_found");
  });

  it("shows empty states", async () => {
    mockFetch(userBootstrap({ admin: true }), (url) =>
      url === "/api/admin/dashboard"
        ? jsonResponse(dashboard({ audit_logs: [], failed_reports: [], daily_activity: [], daily_activity_has_pending: false, response_totals: { total: 0, statuses: [] } }))
        : undefined,
    );
    renderApp("/admin");

    expect(await screen.findByText("No changes recorded yet.")).toBeInTheDocument();
    expect(screen.getByRole("heading", { name: "No failed report deliveries." })).toBeInTheDocument();
    expect(screen.getByText("No responses yet.")).toBeInTheDocument();
    expect(screen.getByText("No standup runs in this period yet.")).toBeInTheDocument();
  });

  it("refreshes", async () => {
    const user = userEvent.setup();
    let calls = 0;
    mockFetch(userBootstrap({ admin: true }), (url) => {
      if (url !== "/api/admin/dashboard") return undefined;
      calls += 1;
      return jsonResponse(dashboard({ stats: { ...dashboard().stats, responses_last_24h: calls === 1 ? 9 : 11 } }));
    });
    renderApp("/admin");

    const responses = (await screen.findByText("Responses (24h)")).parentElement!;
    expect(responses).toHaveTextContent("9");
    await user.click(screen.getByRole("button", { name: "Refresh" }));
    await waitFor(() => expect(responses).toHaveTextContent("11"));
  });

  it("is hidden from non-admins", async () => {
    const fetchMock = mockFetch(userBootstrap());
    renderApp("/admin");

    expect(await screen.findByRole("heading", { name: "Page not found" })).toBeInTheDocument();
    expect(fetchMock.mock.calls.some(([url]) => url === "/api/admin/dashboard")).toBe(false);
  });

  it("shows a load error", async () => {
    mockFetch(userBootstrap({ admin: true }), (url) => (url === "/api/admin/dashboard" ? jsonResponse({ error: "Boom" }, 500) : undefined));
    renderApp("/admin");

    expect(await screen.findByText("Couldn't load the admin dashboard")).toBeInTheDocument();
    expect(screen.getByText("Boom")).toBeInTheDocument();
  });
});
