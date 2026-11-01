import { screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { routes } from "./router";
import { userBootstrap } from "./test/fixtures";
import { mockFetch, renderApp } from "./test/render";

const pages: [string, string][] = [
  ["/manager/standups", "Standups"],
  ["/manager/standups/new", "New standup"],
  ["/manager/standups/7", "Standup"],
  ["/manager/standups/7/edit", "Edit standup"],
  ["/manager/standups/7/analytics", "Insights"],
  ["/manager/standups/7/responses", "Responses"],
  ["/manager/standups/7/participants", "Participants"],
  ["/manager/standups/7/schedule_exceptions", "Schedule"],
  ["/manager/standups/7/report", "Reports"],
  ["/manager/standups/7/chat_setup", "Chat setup"],
  ["/manager/integrations", "Integrations"],
  ["/admin", "Admin"],
  ["/me", "My standups"],
  ["/me/responses", "My responses"],
  ["/me/availability", "Availability"],
  ["/nope", "Page not found"],
];

describe("App", () => {
  it("defines the routes", () => {
    expect(routes).toHaveLength(1);
  });

  it.each(pages)("renders %s", async (path, heading) => {
    mockFetch(userBootstrap({ admin: true, member: { platform: "slack", platform_user_id: "U1", name: "Maya Manager", avatar_url: null } }));
    renderApp(path);
    expect(await screen.findByRole("heading", { level: path === "/nope" ? 2 : 1, name: heading })).toBeInTheDocument();
    expect(document.title).toBe(`${heading} · Standup Bot`);
  });
});
