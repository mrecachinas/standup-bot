# Standup Bot console (frontend)

The web console is a single-page app built with Vite, React, TypeScript,
React Router (data router) and [Primer React](https://primer.style/react).
`npm run build` writes it to `../public/app/`, and Rails' `SpaController`
serves `public/app/index.html` at every console URL (`/manager/...`, `/me/...`,
`/admin`, `/session/new`). All data comes from the JSON API under `/api`.

## Scripts

| Command | What it does |
| --- | --- |
| `npm run dev` | Vite dev server on http://localhost:5173. Proxies `/api` and `/auth` to Rails on :3000. `bin/dev` in the repo root runs both. |
| `npm run build` | Type-checks, then builds into `../public/app/` (assets under `/app/`). |
| `npm run typecheck` | `tsc --noEmit` |
| `npm run lint` | Oxlint (TypeScript + React hooks rules, see `.oxlintrc.json`), no warnings allowed |
| `npm test` / `npm run test:watch` | Vitest + React Testing Library (jsdom), for `src/**/*.test.tsx` |
| `npm run e2e` | Playwright tests in `e2e/` against `script/e2e-server` (build first; see `docs/development.md`) |

## Layout

```
src/
  main.tsx, App.tsx       entry; ThemeRoot + RouterProvider
  router.tsx              every route → a page component
  paths.ts                URL helpers (paths.standup(id), standupTabPath(id, "participants"), …)
  api/client.ts           fetch wrapper: get/post/patch/put/del, ApiError
  api/types.ts            API payload types (Bootstrap, Standup, …)
  session/                SessionProvider (GET /api/session), useSession, route guards
  flash/                  toasts: useFlash().push({ type, message })
  theme/                  ThemeRoot (Primer ThemeProvider + BaseStyles), ThemeSwitch
  layout/                 Root (providers) and AppShell (PageLayout + sidebar)
  hooks/                  useApi, useMutation, useDocumentTitle
  components/             shared UI (import from "../components")
  components/charts/      SVG charts (RunBreakdownChart, RateLineChart, Sparkline, RunLegend)
  lib/                    formatting helpers
  pages/                  one component per route
  test/                   Vitest setup, fixtures, renderApp/mockFetch helpers
```

## Conventions

- **Data loading: hooks, not route loaders.** Pages call
  `useApi<T>(path)` → `{ data, error, loading, reload, setData }`. Writes use
  `useMutation(fn, options)` → `{ run, loading, error, reset }`; `run` never
  rejects (it returns `undefined` and sets `error`). Show `error` with
  `<ErrorBanner error={error} />` and per-field messages with
  `error?.fieldError("name")` in `FormControl.Validation`.
- **API client.** Use `get/post/patch/del` from `api/client`. It sends the
  session cookie, JSON and the `X-CSRF-Token` header, refreshes the session
  and retries once on "Invalid authenticity token", and on a 401 re-fetches
  the session so the guards send the person to `/session/new?next=…`.
  Errors are `ApiError` (`status`, `message`, `errors`, `fieldErrors`).
- **Flash messages.** `useMutation` shows the response's `notice` as a success
  toast automatically (override with `successMessage`, or `false`). Anywhere
  else: `useFlash().push({ type: "success" | "warning" | "danger", message })`.
  Server flashes from the bootstrap (e.g. a failed Slack sign-in) show up the
  same way.
- **Sidebar.** After creating, renaming, pausing/resuming or deleting a
  standup, refresh the bootstrap: pass `refreshSidebar: true` to
  `useMutation`, or call `useRefreshSidebar()()` / `useSession().refresh()`.
- **Session.** `useSession()` → `{ bootstrap, refresh, signIn, signOut, consumeFlash }`.
  `bootstrap.user` is the manager/admin, `bootstrap.member` the Slack/Teams
  identity, `bootstrap.platforms` the per-platform labels and copy.
- **Titles.** Every page calls `useDocumentTitle("Participants")` →
  "Participants · Standup Bot".
- **Styling.** Primer components first; layout tweaks in a co-located
  `*.module.css` using Primer CSS variables (`var(--fgColor-muted)`,
  `var(--base-size-16)`, …). No hard-coded colours, so light and dark both work.

## Adding a page

1. Create `src/pages/<area>/<Name>Page.tsx` exporting `function <Name>Page()`.
   Placeholders already exist for every console route; replace their body.
2. Register it in `src/router.tsx` under the right guard (`RequireUser`,
   `RequireUser admin`, or `RequireMember`) if it isn't there yet.
3. Use `useParams()` for ids, `useApi` / `useMutation` for data,
   `PageHeader` (or `StandupHeader` for standup tabs) for the header.
4. Add a test next to it (`*.test.tsx`). `renderApp(path)` + `mockFetch(bootstrap, handler)`
   from `src/test/render.tsx` render the whole app with a stubbed API.

## Shared components

| Component | Props |
| --- | --- |
| `Avatar` | `name`, `src?`, `size?` (px, 32), `square?` — photo over coloured initials |
| `AvatarStack` | `people: ({ name, avatar_url? } \| string)[]`, `limit?` (5), `size?` |
| `StatusLabel` | `tone: "success" \| "info" \| "warning" \| "danger" \| null`, `size?`, children |
| `StandupStatusLabel` | `active: boolean` |
| `StatCard` / `StatGrid` | `label`, `value`, `hint?`, `tone?`, `icon?`, children |
| `PageHeader` | `title`, `description?`, `actions?`, `breadcrumbs?: { label, to? }[]`, `trailingVisual?`, children (meta row) |
| `StandupHeader` | `standup` (StandupSerializer payload), `active: StandupTab`, `onPauseResume?`, `pauseResumeBusy?`, `participantCount?` |
| `EmptyState` | `title`, `description?`, `icon?`, `action?`, `secondaryAction?`, `border?`, `narrow?`, `size?` |
| `RelativeTime` | `datetime`, `fallback?` ("—") |
| `ConfirmButton` | Button props + `title`, `message?`, `confirmLabel?`, `danger?`, `onConfirm` |
| `ErrorBanner` | `error` (ApiError/Error/string/null), `title?`, `action?`, `onDismiss?` |
| `LoadingState` | `label?`, `fullPage?` |
| Charts | `RunBreakdownChart({ runs })`, `RateLineChart({ points })`, `Sparkline({ values })`, `RunLegend({ pending })` |

Formatting helpers (`formatPercent`, `pluralize`, `toSentence`,
`formatRelativeTime`, `parseApiDate`, …) are re-exported from `components`.
