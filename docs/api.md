# API

Standup Bot has one JSON API under `/api`. Scripts use it with a person's access token, and the web console uses it with that person's session. Either way, requests act as that person. There are also a few health check endpoints for load balancers and monitoring.

## Authentication

Each request uses exactly one of these:

- **Access token** (scripts). Send a person's access token, the same one they can sign in with, in the `Authorization` header:

  ```bash
  curl -H "Authorization: Bearer $STANDUP_BOT_TOKEN" http://localhost:3000/api/standups
  ```

  Here `STANDUP_BOT_TOKEN` is just a shell variable holding the token. The request acts as that person: it sees and changes only the standups they manage (admins see all of them), and changes are recorded in the audit log as them. See [Accounts](configuration.md#accounts) for creating accounts and tokens.
- **Session cookie** (the console). The browser signs in through `/auth/slack`, `/auth/microsoft`, or `POST /api/session`, and gets a session cookie. Requests that change data must also send the CSRF token from `GET /api/session` in an `X-CSRF-Token` header.

Any request with an `Authorization` header counts as a token request: the session cookie is ignored and CSRF doesn't apply. If the token is wrong, or belongs to a turned-off account, you get `401`, even when the browser also sent a valid session cookie. `/api/session` and the member area (`/api/me/*`) only work with a session.

> **Changed with the React console:** the shared `ADMIN_API_TOKEN` is gone. Use an admin's access token instead to keep the same access. Requests with no `Authorization` header are session requests, so they get `401` unless someone is signed in.

Rate limits: 600 requests a minute per IP across `/api`, and 10 sign-ins a minute per IP and 5 per email. After 10 wrong tokens in a minute, the IP is blocked from `/api` for 10 minutes (`403 {"error": "blocked"}`).

## Errors

Errors are JSON. Validation failures return `422` with the full messages, plus the same messages grouped by field:

```json
{ "errors": ["Name can't be blank"], "field_errors": { "name": ["can't be blank"] } }
```

`field_errors` is new; `errors` is unchanged.

## Standups API

These endpoints have been around since before the console, and their responses keep the same keys. The console asks for extra data with query parameters (for example `?include=overview` or `?view=history`), so scripts don't pay for it.

### Endpoints

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/api/standups` | List all standups |
| `POST` | `/api/standups` | Create a standup |
| `GET` | `/api/standups/:id` | Get one standup |
| `PATCH` | `/api/standups/:id` | Update a standup |
| `DELETE` | `/api/standups/:id` | Delete a standup |
| `GET` | `/api/standups/:id/participants` | List participants |
| `POST` | `/api/standups/:id/participants` | Add a participant |
| `DELETE` | `/api/standups/:id/participants/:participant_id` | Remove a participant |
| `GET` | `/api/standups/:id/responses` | List responses. Filter with `status`, `platform_user_id`, `since`, `until`, and `limit` (default 100, max 500). |
| `GET` | `/api/standups/:id/stats` | Summary stats. Pass `period_days` to change the window (default 30). |
| `GET` | `/api/standups/:id/analytics` | Detailed analytics, also with `period_days` |

Responses may include extra keys the console uses, such as `schedule_summary` or `status_label` on standups. New keys are only ever added.

### Fields

Standups have a `platform` (`slack` by default) and a `platform_channel` where updates are posted. `platform` is set when the standup is created and can't be changed later. Participants and responses identify people by `platform_user_id`, and participants have a `display_name`. Responses also include the DM channel (`dm_channel`) and the ID of the channel post (`platform_message_id`).

> **Changed in the platform-neutral schema:** these fields used to be `slack_channel`, `slack_id`, `slack_name`, and `slack_message_ts` (and `slack_channel` on responses). The old names are no longer accepted or returned.

### Examples

Create a standup:

```bash
curl -X POST http://localhost:3000/api/standups \
  -H "Authorization: Bearer $STANDUP_BOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "standup": {
      "name": "Platform Daily",
      "platform": "slack",
      "platform_channel": "platform-standup",
      "schedule_type": "weekdays",
      "default_hour": 9,
      "default_minute": 30,
      "questions": ["What did you do yesterday?", "What are you doing today?", "Any blockers?"]
    }
  }'
```

Add a participant:

```bash
curl -X POST http://localhost:3000/api/standups/1/participants \
  -H "Authorization: Bearer $STANDUP_BOT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "participant": { "platform_user_id": "U01ABC123", "display_name": "Sarah Thompson" } }'
```

Get completed responses since a given date:

```bash
curl -H "Authorization: Bearer $STANDUP_BOT_TOKEN" \
  "http://localhost:3000/api/standups/1/responses?status=completed&since=2026-10-01"
```

## Console endpoints

The console uses these too, and so can scripts with an access token, except where noted. They're shaped for the console's pages, so treat their payloads as less stable than the standups API above. See `app/controllers/api/` for the details.

| Path | What it's for |
| --- | --- |
| `GET/POST/DELETE /api/session` | Console bootstrap, email + access token sign-in, and sign-out. Session only. |
| `GET /api/overview` | The standups overview page |
| `GET /api/standups/new`, `GET /api/standups/:id/edit` | Form data for the standup editor |
| `POST /api/standups/preview` | Upcoming send times for a draft schedule |
| `PATCH /api/standups/:id/pause`, `/resume` | Pause or resume a standup |
| `GET /api/standups/channel_options` | Channels for the editor's picker: Teams' list, or a Slack search with `?platform=slack&query=` (private channels only for admins) |
| `GET /api/people` | Search people on a chat platform |
| `/api/standups/:id/participants/...` | Also `PATCH`, `bulk_import`, `sync`, and `?view=console` |
| `/api/standups/:id/managers` | Make someone a manager, or remove them |
| `/api/standups/:id/schedule_exceptions` | Skips, holidays, and reschedules |
| `GET /api/standups/:id/responses?view=history` | Response history by day |
| `GET /api/standups/:id/analytics?view=insights`, `.csv` | Insights page and CSV export |
| `/api/standups/:id/report` | Report settings and on-demand reports |
| `/api/standups/:id/chat_setup` | Summary channel, channel discovery, and test messages for one standup |
| `GET /api/integrations` | Slack and Teams connection status and discovery |
| `GET /api/admin/dashboard` | Installation health, usage, users, and audit log. Admins only. |
| `/api/me/standups`, `/api/me/responses`, `/api/me/availability` | The signed-in member's own standups, answers, and time away. Session only. |

## Health checks

These endpoints don't need authentication.

| Path | Returns |
| --- | --- |
| `/up` | `200` if the app booted. Used by the Docker and Kamal health checks. |
| `/health` | A basic `{ "status": "ok" }` response |
| `/health/detailed` | Database, job queue, and Slack API checks, with an overall status |
| `/health/metrics` | Operational metrics for dashboards |
