# Development

To get the app running locally first, see [Getting started](getting-started.md).

## Running the app

```bash
bin/dev                 # Rails on :3000 and the console's Vite dev server on :5173
```

Open <http://localhost:5173>. Vite reloads the console as you edit it and passes `/api` and `/auth` requests through to Rails. `script/server` does the same after preparing and seeding the database. If you only need Rails (for example to work on Slack webhooks), run `bin/dev --rails-only`. To serve the built console from Rails itself on port 3000, run `npm run build` in `frontend/` first.

You'll need Node (the version in [`.node-version`](../.node-version)) for the console. `script/bootstrap` installs its packages, and `bin/dev` does too if they're missing.

## Tests

The Rails suite uses Minitest with Mocha and runs against MySQL.

```bash
script/test                                   # start MySQL if needed, prepare the test DB, run everything
script/test test/models/standup_test.rb       # run one file
bin/rails test test/services/                 # or call Rails directly if the DB is already up
```

The console has its own checks, run from `frontend/`:

```bash
npm test                                      # Vitest + React Testing Library
npm run typecheck                             # TypeScript
npm run lint                                  # ESLint
npm run build                                 # build into public/app
```

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
| `app/controllers/api/` | The JSON API, for scripts (admin token) and the console (session) |
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
Make sure your request URL is publicly reachable (use ngrok locally) and that `SLACK_SIGNING_SECRET` matches the app's signing secret. Requests that fail verification are logged and rejected.

**The bot doesn't respond to DMs.**
Check that the app is subscribed to the `message.im` event, has the `im:history` and `im:write` scopes, and is installed in the workspace. Also check that the job worker (`bin/jobs`) is running, since DMs are handled in the background.

**No standups are going out.**
The worker has to be running for scheduled DMs to be sent. Check that the standup is active, has active participants, and isn't paused or skipped for today by a schedule exception.

**Standups go out at the wrong time.**
When a standup respects timezones, it uses each participant's Slack timezone. If someone's timezone is wrong, fix it in their Slack profile. The bot caches timezones, so the change may take a little while to show up.

**Where are the logs?**
In development, they're in `log/development.log` and the server output. In production, they go to stdout, so use `docker compose logs` or `kamal app logs`.
