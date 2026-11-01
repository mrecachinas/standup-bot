import { createBrowserRouter, type RouteObject } from "react-router";
import { AppShell } from "./layout/AppShell";
import { Root } from "./layout/Root";
import { RouteErrorPage } from "./pages/RouteErrorPage";
import { NotFoundPage } from "./pages/NotFoundPage";
import { SignInPage } from "./pages/session/SignInPage";
import { MyStandupsPage } from "./pages/me/MyStandupsPage";
import { MyResponsesPage } from "./pages/me/MyResponsesPage";
import { AvailabilityPage } from "./pages/me/AvailabilityPage";
import { StandupsIndexPage } from "./pages/manager/StandupsIndexPage";
import { NewStandupPage } from "./pages/manager/NewStandupPage";
import { StandupPage } from "./pages/manager/StandupPage";
import { EditStandupPage } from "./pages/manager/EditStandupPage";
import { StandupAnalyticsPage } from "./pages/manager/StandupAnalyticsPage";
import { StandupResponsesPage } from "./pages/manager/StandupResponsesPage";
import { StandupParticipantsPage } from "./pages/manager/StandupParticipantsPage";
import { ScheduleExceptionsPage } from "./pages/manager/ScheduleExceptionsPage";
import { StandupReportPage } from "./pages/manager/StandupReportPage";
import { ChatSetupPage } from "./pages/manager/ChatSetupPage";
import { IntegrationsPage } from "./pages/manager/IntegrationsPage";
import { AdminDashboardPage } from "./pages/admin/AdminDashboardPage";
import { HomeRedirect, RequireMember, RequireUser } from "./session/guards";

/**
 * Console routes. Paths match the Rails routes that SpaController serves, so
 * bookmarks and links from Slack/Teams keep working.
 */
export const routes: RouteObject[] = [
  {
    element: <Root />,
    errorElement: <RouteErrorPage />,
    children: [
      { path: "/session/new", element: <SignInPage /> },
      { path: "/", element: <HomeRedirect /> },
      {
        element: <AppShell />,
        children: [
          {
            element: <RequireMember />,
            children: [
              { path: "/me", element: <MyStandupsPage /> },
              { path: "/me/responses", element: <MyResponsesPage /> },
              { path: "/me/availability", element: <AvailabilityPage /> },
            ],
          },
          {
            element: <RequireUser />,
            children: [
              { path: "/manager/standups", element: <StandupsIndexPage /> },
              { path: "/manager/standups/new", element: <NewStandupPage /> },
              { path: "/manager/standups/:id", element: <StandupPage /> },
              { path: "/manager/standups/:id/edit", element: <EditStandupPage /> },
              { path: "/manager/standups/:id/analytics", element: <StandupAnalyticsPage /> },
              { path: "/manager/standups/:id/responses", element: <StandupResponsesPage /> },
              { path: "/manager/standups/:id/participants", element: <StandupParticipantsPage /> },
              { path: "/manager/standups/:id/schedule_exceptions", element: <ScheduleExceptionsPage /> },
              { path: "/manager/standups/:id/report", element: <StandupReportPage /> },
              { path: "/manager/standups/:id/chat_setup", element: <ChatSetupPage /> },
              { path: "/manager/integrations", element: <IntegrationsPage /> },
            ],
          },
          {
            element: <RequireUser admin />,
            children: [{ path: "/admin", element: <AdminDashboardPage /> }],
          },
          { path: "*", element: <NotFoundPage /> },
        ],
      },
    ],
  },
];

export function createRouter() {
  return createBrowserRouter(routes);
}
