import type { ComponentType } from "react";
import { createBrowserRouter, type RouteObject } from "react-router";
import { AppShell } from "./layout/AppShell";
import { Root } from "./layout/Root";
import { RouteErrorPage } from "./pages/RouteErrorPage";
import { NotFoundPage } from "./pages/NotFoundPage";
import { SignInPage } from "./pages/session/SignInPage";
import { HomeRedirect, RequireMember, RequireUser } from "./session/guards";
import { LoadingState } from "./components";

/**
 * Console routes. Paths match the Rails routes that SpaController serves, so
 * bookmarks and links from Slack/Teams keep working. Pages load on demand, so
 * the first visit only downloads the shell and the page being opened.
 */
export const routes: RouteObject[] = [
  {
    element: <Root />,
    errorElement: <RouteErrorPage />,
    hydrateFallbackElement: <LoadingState fullPage />,
    children: [
      { path: "/session/new", element: <SignInPage /> },
      { path: "/", element: <HomeRedirect /> },
      {
        element: <AppShell />,
        children: [
          {
            element: <RequireMember />,
            children: [
              { path: "/me", lazy: page(() => import("./pages/me/MyStandupsPage"), "MyStandupsPage") },
              { path: "/me/responses", lazy: page(() => import("./pages/me/MyResponsesPage"), "MyResponsesPage") },
              { path: "/me/availability", lazy: page(() => import("./pages/me/AvailabilityPage"), "AvailabilityPage") },
            ],
          },
          {
            element: <RequireUser />,
            children: [
              { path: "/manager/standups", lazy: page(() => import("./pages/manager/StandupsIndexPage"), "StandupsIndexPage") },
              { path: "/manager/standups/new", lazy: page(() => import("./pages/manager/NewStandupPage"), "NewStandupPage") },
              { path: "/manager/standups/:id", lazy: page(() => import("./pages/manager/StandupPage"), "StandupPage") },
              { path: "/manager/standups/:id/edit", lazy: page(() => import("./pages/manager/EditStandupPage"), "EditStandupPage") },
              { path: "/manager/standups/:id/analytics", lazy: page(() => import("./pages/manager/StandupAnalyticsPage"), "StandupAnalyticsPage") },
              { path: "/manager/standups/:id/responses", lazy: page(() => import("./pages/manager/StandupResponsesPage"), "StandupResponsesPage") },
              { path: "/manager/standups/:id/participants", lazy: page(() => import("./pages/manager/StandupParticipantsPage"), "StandupParticipantsPage") },
              { path: "/manager/standups/:id/schedule_exceptions", lazy: page(() => import("./pages/manager/ScheduleExceptionsPage"), "ScheduleExceptionsPage") },
              { path: "/manager/standups/:id/report", lazy: page(() => import("./pages/manager/StandupReportPage"), "StandupReportPage") },
              { path: "/manager/standups/:id/chat_setup", lazy: page(() => import("./pages/manager/ChatSetupPage"), "ChatSetupPage") },
              { path: "/manager/integrations", lazy: page(() => import("./pages/manager/IntegrationsPage"), "IntegrationsPage") },
            ],
          },
          {
            element: <RequireUser admin />,
            children: [{ path: "/admin", lazy: page(() => import("./pages/admin/AdminDashboardPage"), "AdminDashboardPage") }],
          },
          { path: "*", element: <NotFoundPage /> },
        ],
      },
    ],
  },
];

/** A route whose page component is downloaded the first time it's visited. */
function page<Name extends string>(load: () => Promise<Record<Name, ComponentType>>, name: Name) {
  return async () => ({ Component: (await load())[name] });
}

export function createRouter() {
  return createBrowserRouter(routes);
}
