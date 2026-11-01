import { screen, waitFor } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import { routes } from "./router";
import { userBootstrap } from "./test/fixtures";
import { mockFetch, renderApp } from "./test/render";

const paths = [
  "/manager/standups",
  "/manager/standups/new",
  "/manager/standups/7",
  "/manager/standups/7/edit",
  "/manager/standups/7/analytics",
  "/manager/standups/7/responses",
  "/manager/standups/7/participants",
  "/manager/standups/7/schedule_exceptions",
  "/manager/standups/7/report",
  "/manager/standups/7/chat_setup",
  "/manager/integrations",
  "/admin",
  "/me",
  "/me/responses",
  "/me/availability",
  "/nope",
];

describe("App", () => {
  it("defines the routes", () => {
    expect(routes).toHaveLength(1);
  });

  // Every page's own API call 404s here, so this checks each route renders and
  // handles a failed load without falling through to the route error page.
  it.each(paths)("renders %s without crashing when its data can't load", async (path) => {
    mockFetch(userBootstrap({ admin: true, member: { platform: "slack", platform_user_id: "U1", name: "Maya Manager", avatar_url: null } }));
    renderApp(path);

    await waitFor(() => expect(document.title).toMatch(/ · Standup Bot$/));
    await waitFor(() => expect(screen.queryByText(/^Loading/)).not.toBeInTheDocument());
    expect(screen.queryByRole("heading", { name: "Something went wrong" })).not.toBeInTheDocument();
  });
});
