# Development

To get the app running locally first, see [Getting started](getting-started.md).

## Running the app

```bash
bin/dev                 # Rails on :3000, the console's Vite dev server on :5173, and the job worker
```

Open <http://localhost:5173>. Vite reloads the console as you edit it and passes `/api` and `/auth` requests through to Rails. `script/server` does the same after preparing and seeding the database. If you only need Rails (for example to work on Slack webhooks), run `bin/dev --rails-only`; jobs are queued but won't run until you start `bin/jobs`. To serve the built console from Rails itself on port 3000, run `npm run build` in `frontend/` first.

Background jobs work the same way as in production: Solid Queue stores them in a separate `nerdbot_development_queue` database, and `bin/dev` starts the worker (`bin/jobs`). The worker also runs the recurring schedule in [`config/recurring.yml`](../config/recurring.yml), so scheduled standups and reminders go out locally. Set `SOLID_QUEUE_IN_PUMA=1` to run the worker inside Rails instead. `bin/rails db:prepare` (which `script/server` and `bin/setup` run) creates and loads the queue database. Worker output goes to `log/development.log`.

> [!WARNING]
> The recurring schedule is real. While `bin/dev` is running against a real Slack or Teams workspace, every active standup that comes due DMs its actual participants, reminders follow, and the nightly `DataCleanupJob` prunes old responses from your dev database. To turn the schedule off and still run jobs you trigger yourself, set `SOLID_QUEUE_SKIP_RECURRING=1`:
>
> ```bash
> SOLID_QUEUE_SKIP_RECURRING=1 bin/dev
> ```
>
> Solid Queue reads this variable in `bin/jobs` and when it runs inside Puma (`SOLID_QUEUE_IN_PUMA=1`). `bin/dev` prints whether recurring jobs are on when it starts. To run one scheduled pass by hand, use `bin/rails runner 'SchedulingJob.perform_later'`.

If you point development at another database with `DATABASE_URL`, the queue database uses the same connection with a `_queue` suffix (for example `nerdbot_mine` and `nerdbot_mine_queue`). `QUEUE_DB_NAME` picks a different name, and `QUEUE_DATABASE_URL` overrides the queue connection entirely ([`lib/development_queue_database.rb`](../lib/development_queue_database.rb) has the rules). The development cache is a file store in `tmp/cache/store`, shared by Rails, the worker, and the Socket Mode client, so the Admin page shows Socket Mode activity. `bin/rails tmp:cache:clear` empties it.

You'll need Node (the version in [`.node-version`](../.node-version)) for the console. `script/bootstrap` installs its packages, and `bin/dev` does too if they're missing.

### Migrations

App migrations live in `db/migrate` and belong to the `primary` database. `bin/rails db:migrate` migrates both databases and updates `db/schema.rb`. It leaves `db/queue_schema.rb` alone: that's Solid Queue's stock schema, which production loads into PostgreSQL, so it isn't regenerated from the MySQL queue database. Because development has two databases, tasks that act on a single migration need the `:primary` suffix:

```bash
bin/rails db:rollback:primary
bin/rails db:migrate:redo:primary
bin/rails db:migrate:up:primary VERSION=20260101000000
bin/rails db:migrate:down:primary VERSION=20260101000000
```

## Tests

The Rails suite uses Minitest with Mocha and runs against MySQL by default.

```bash
script/test                                   # start MySQL if needed, prepare the test DB, run everything
script/test test/models/standup_test.rb       # run one file
bin/rails test test/services/                 # or call Rails directly if the DB is already up
```

Production runs PostgreSQL, so CI also runs the suite there. To do the same locally, point the test environment at a PostgreSQL server:

```bash
RAILS_ENV=test TEST_DB_ADAPTER=postgresql DB_HOST=localhost bin/rails db:test:prepare test
```

Keep `RAILS_ENV=test`. Without it, `db:test:prepare` connects to the development database (MySQL) first and fails if MySQL isn't running. `DB_USER` defaults to your login name and `DB_PORT` to 5432. On macOS, also set `PGGSSENCMODE=disable`, or the forked test workers can crash in libpq. Watch out for PostgreSQL-only differences, such as `DISTINCT` over tables with `json` columns (`standups`, `standup_responses`), which PostgreSQL can't compare. Use a subquery instead.

The console has its own checks, run from `frontend/`:

```bash
npm test                                      # Vitest + React Testing Library
npm run typecheck                             # TypeScript
npm run lint                                  # Oxlint
npm run build                                 # build into public/app
```

End-to-end tests drive the built console in Chromium, in light and dark mode, against a real Rails server. That server runs in development mode (so CSRF and sessions behave as in production) against a throwaway `nerdbot_e2e` database (plus `nerdbot_e2e_queue`) loaded with the test fixtures. No job worker runs, so jobs are queued but never performed. They need MySQL running. Only one Rails server can run per checkout, so stop `bin/dev` first.

```bash
cd frontend
npm run build
npx playwright install chromium               # first time only
npm run e2e                                   # starts script/e2e-server on port 3100
```

They cover signing in and out, creating, editing, pausing and resuming a standup, importing people, every standup tab, access rules, the admin pages, and the member area, and they fail on console errors. To reach the member area, the e2e server fakes Slack's token exchange (`config/initializers/e2e_fake_slack_sign_in.rb`, enabled only by `E2E_FAKE_SLACK_SIGN_IN=1` and refused in production), and the tests skip the visit to slack.com while the rest of sign-in runs for real.

## Linting and security checks

These are the same checks that CI runs, along with the console checks above:

```bash
bin/rubocop                                   # style (Rails Omakase); add -A to auto-fix
bin/brakeman --no-pager                       # static security analysis
bundle exec bundler-audit check --update      # known-vulnerable gems
bin/rails standups:validate                   # check config/standups/*.yml
```

## Useful tasks

| Command | What it does |
| --- | --- |
| `APP_URL=https://… bin/rails slack:manifest` | Print a Slack app manifest for that URL |
| `bin/rails standups:validate` | Check the YAML standup files |
| `bin/rails standups:import` | Load the YAML standup files into the database |
| `bin/rails db:seed` | Create the admin set by `MANAGER_ADMIN_EMAIL` and `MANAGER_ADMIN_TOKEN` |

## Project layout

| Path | What's there |
| --- | --- |
| `app/controllers/slack_*` | Slack events, interactions, and slash commands |
| `app/controllers/api/` | The JSON API, for scripts (access token) and the console (session) |
| `app/serializers/` | JSON shapes and display values for the API |
| `app/controllers/spa_controller.rb` | Serves the console's `index.html` for console URLs |
| `frontend/` | The web console: React, TypeScript, and Primer React (see [`frontend/README.md`](../frontend/README.md)) |
| `app/jobs/` | Scheduling, DMs, reminders, reports, and cleanup |
| `app/services/` | Slack client, response handling, analytics, and audit logging |
| `config/standups/` | YAML standup definitions |
| `config/recurring.yml` | Recurring job schedule |

[Architecture](architecture.md) explains how these fit together.

## Troubleshooting

**Slack events aren't arriving.**
In HTTP mode, make sure your request URL is publicly reachable (use ngrok locally) and that `SLACK_SIGNING_SECRET` matches the app's signing secret. Requests that fail verification are logged and rejected. In Socket Mode, check that `bin/slack-socket-mode` is running (or `SLACK_SOCKET_MODE_IN_PUMA` is set), that its logs say "Slack Socket Mode connected", and that Socket Mode is turned on in the Slack app's settings. Locally, Socket Mode avoids the tunnel entirely: set `SLACK_CONNECTION_MODE=socket` and `SLACK_APP_TOKEN`, and `bin/dev` starts the client.

**The bot doesn't respond to DMs.**
Check that the app is subscribed to the `message.im` event, has the `im:history` and `im:write` scopes, and is installed in the workspace. Also check that the job worker is running, since DMs are handled in the background. `bin/dev` starts it locally; if you ran `bin/dev --rails-only`, start `bin/jobs` yourself.

**No standups are going out.**
The worker has to be running for scheduled DMs to be sent. It checks for standups that are due every hour and sends reminders every 15 minutes, so you may need to wait for the next run. To run them now, use `bin/rails runner 'SchedulingJob.perform_later'` (or `StandupReminderJob`). If `bin/jobs` fails with `Table '…solid_queue_processes' doesn't exist`, run `bin/rails db:prepare` to create the queue database. Also check that the standup is active, has active participants, and isn't paused or skipped for today by a schedule exception.

**Standups go out at the wrong time.**
When a standup respects timezones, it uses each participant's Slack timezone. If someone's timezone is wrong, fix it in their Slack profile. The bot caches timezones, so the change may take a little while to show up.

**Where are the logs?**
In development, they're in `log/development.log` and the server output. In production, they go to stdout, so use `docker compose logs` or `kamal app logs`.
