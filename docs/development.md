# Development

To get the app running locally first, see [Getting started](getting-started.md).

## Tests

The suite uses Minitest with Mocha and runs against MySQL.

```bash
script/test                                   # start MySQL if needed, prepare the test DB, run everything
script/test test/models/standup_test.rb       # run one file
bin/rails test test/services/                 # or call Rails directly if the DB is already up
```

## Linting and security checks

These are the same checks that CI runs:

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
| `app/controllers/manager/` | The manager web console |
| `app/controllers/api/` | The admin JSON API |
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
