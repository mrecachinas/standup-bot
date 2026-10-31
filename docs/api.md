# API

Standup Bot has a small JSON API for scripts and internal tools, plus a few health check endpoints for load balancers and monitoring.

## Admin API

Every `/api/*` request needs the admin token in the `Authorization` header:

```bash
curl -H "Authorization: Bearer $ADMIN_API_TOKEN" http://localhost:3000/api/standups
```

Set the token with the `ADMIN_API_TOKEN` environment variable, or store it in Rails credentials as `admin.api_token`. If it's missing or wrong, the API returns `401`. Changes made through the API are recorded in the audit log.

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
| `GET` | `/api/standups/:id/responses` | List responses. Filter with `status`, `slack_id`, `since`, `until`, and `limit` (default 100, max 500). |
| `GET` | `/api/standups/:id/stats` | Summary stats. Pass `period_days` to change the window (default 30). |
| `GET` | `/api/standups/:id/analytics` | Detailed analytics, also with `period_days` |

### Examples

Create a standup:

```bash
curl -X POST http://localhost:3000/api/standups \
  -H "Authorization: Bearer $ADMIN_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "standup": {
      "name": "Platform Daily",
      "slack_channel": "platform-standup",
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
  -H "Authorization: Bearer $ADMIN_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "participant": { "slack_id": "U01ABC123", "slack_name": "Sarah Thompson" } }'
```

Get completed responses since a given date:

```bash
curl -H "Authorization: Bearer $ADMIN_API_TOKEN" \
  "http://localhost:3000/api/standups/1/responses?status=completed&since=2026-10-01"
```

## Health checks

These endpoints don't need authentication.

| Path | Returns |
| --- | --- |
| `/up` | `200` if the app booted. Used by the Docker and Kamal health checks. |
| `/health` | A basic `{ "status": "ok" }` response |
| `/health/detailed` | Database, job queue, and Slack API checks, with an overall status |
| `/health/metrics` | Operational metrics for dashboards |
