/** Console URLs. They match the Rails routes, so bookmarks and chat links keep working. */
export type StandupTab = "overview" | "insights" | "responses" | "participants" | "settings";

/** The pages listed in a standup's Settings side nav. */
export type SettingsSection = "general" | "schedule" | "reports";

type Id = number | string;

export const paths = {
  home: "/",
  signIn: "/session/new",
  me: "/me",
  myResponses: "/me/responses",
  availability: "/me/availability",
  standups: "/manager/standups",
  newStandup: "/manager/standups/new",
  integrations: "/manager/integrations",
  admin: "/admin",
  standup: (id: Id) => `/manager/standups/${id}`,
  editStandup: (id: Id) => `/manager/standups/${id}/edit`,
  standupAnalytics: (id: Id) => `/manager/standups/${id}/analytics`,
  standupResponses: (id: Id) => `/manager/standups/${id}/responses`,
  standupParticipants: (id: Id) => `/manager/standups/${id}/participants`,
  standupScheduleExceptions: (id: Id) => `/manager/standups/${id}/schedule_exceptions`,
  standupReport: (id: Id) => `/manager/standups/${id}/report`,
} as const;

export function standupTabPath(id: Id, tab: StandupTab): string {
  switch (tab) {
    case "overview":
      return paths.standup(id);
    case "insights":
      return paths.standupAnalytics(id);
    case "responses":
      return paths.standupResponses(id);
    case "participants":
      return paths.standupParticipants(id);
    case "settings":
      return paths.editStandup(id);
  }
}

export function settingsPath(id: Id, section: SettingsSection): string {
  switch (section) {
    case "general":
      return paths.editStandup(id);
    case "schedule":
      return paths.standupScheduleExceptions(id);
    case "reports":
      return paths.standupReport(id);
  }
}
