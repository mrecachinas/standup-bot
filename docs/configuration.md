# Configuration

Standup Bot is configured with environment variables. You can set up standups themselves in the web console or in YAML files.

## Environment variables

### Slack

| Variable | Required | Description |
| --- | --- | --- |
| `SLACK_BOT_TOKEN` | Yes, to use Slack | Bot User OAuth Token (`xoxb-…`) |
| `SLACK_CONNECTION_MODE` | No | How Slack reaches the app: `http` (default, public request URLs) or `socket` ([Socket Mode](slack-setup.md#run-the-socket-mode-client), no public URL needed) |
| `SLACK_SIGNING_SECRET` | Yes, in `http` mode | Used to verify that requests really come from Slack |
| `SLACK_APP_TOKEN` | Yes, in `socket` mode | App-level token (`xapp-…`) with the `connections:write` scope |
| `SLACK_SOCKET_MODE_IN_PUMA` | No | In `socket` mode, set it to hold the Socket Mode connection in the web process instead of running `bin/slack-socket-mode` |
| `SLACK_CLIENT_ID` | No | Slack app client ID. Needed for "Sign in with Slack" |
| `SLACK_CLIENT_SECRET` | No | Slack app client secret. Needed for "Sign in with Slack" |
| `SLACK_TEAM_ID` | No | Workspace (`T…`) allowed to use "Sign in with Slack". Defaults to the bot token's workspace |

See [Slack setup](slack-setup.md) for where to find these.

### Microsoft Teams

| Variable | Required | Description |
| --- | --- | --- |
| `TEAMS_APP_ID` | Yes, to use Teams | Application (client) ID of the Azure Bot's app registration |
| `TEAMS_APP_PASSWORD` | Yes, to use Teams | Client secret for that app registration |
| `TEAMS_TENANT_ID` | Yes, to use Teams | Microsoft Entra tenant the bot and "Sign in with Microsoft" are pinned to |
| `TEAMS_SERVICE_URL` | No | Bot Connector URL for proactive messages. Defaults to `https://smba.trafficmanager.net/teams/` |
| `TEAMS_APP_CATALOG_ID` | No | Teams app catalog ID, so the bot can install itself for participants |
| `TEAMS_SIGN_IN_CLIENT_ID`, `TEAMS_SIGN_IN_CLIENT_SECRET` | No | A separate app registration for "Sign in with Microsoft". Defaults to the bot's |

See [Microsoft Teams setup](teams-setup.md) for where to find these and which Graph permissions to grant. You can configure Slack, Teams, or both. Each standup picks one.

### Access

| Variable | Description |
| --- | --- |
| `MANAGER_ADMIN_EMAIL`, `MANAGER_ADMIN_TOKEN`, `MANAGER_ADMIN_NAME` | When the email and token are both set, `bin/rails db:seed` creates or updates an admin user for the web console. |

### Database

In production, the app uses PostgreSQL with three databases: the main one, plus separate ones for the Solid Cache and Solid Queue stores.

| Variable | Description |
| --- | --- |
| `DATABASE_URL` | Main database |
| `CACHE_DATABASE_URL`, `QUEUE_DATABASE_URL` | The cache and queue databases |
| `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` | An alternative to `DATABASE_URL`. These also set the MySQL connection in development and test. |

The cache and queue databases also accept `CACHE_DB_*` and `QUEUE_DB_*` overrides. Anything you don't set falls back to the matching `DB_*` value.

Development uses MySQL with two databases: the main one and `nerdbot_development_queue` for Solid Queue (there's no separate cache database). If you set `DATABASE_URL`, the queue database uses the same connection with a `_queue` suffix on the database name (or `nerdbot_development_queue` if the URL names no database). `QUEUE_DB_NAME` sets the queue database's name, and `QUEUE_DATABASE_URL` replaces its connection entirely. Test uses a single database and doesn't need a queue database.

### Operations

| Variable | Default | Description |
| --- | --- | --- |
| `ADMIN_CHANNEL` | _(unset)_ | Slack channel that gets a message when a background job fails (at most once per kind of failure every 15 minutes) |
| `TEAMS_ADMIN_CHANNEL` | _(unset)_ | Teams channel (`TEAM_ID\|CHANNEL_ID`) that gets a message when a background job fails |
| `RESPONSE_RETENTION_DAYS` | `90` | How long to keep standup responses |
| `STALE_PENDING_DAYS` | `7` | When unanswered standups are marked expired |
| `CLEANUP_BATCH_SIZE` | `1000` | Rows per batch in the nightly cleanup job |
| `JOB_CONCURRENCY` | `1` | Number of job worker processes for scheduled work. What people send the bot always has its own worker process (`inbound` queue in `config/queue.yml`). |
| `STANDUP_SEND_CONCURRENCY` | `2` | How many first messages of a standup are sent at once, so a standup going to everyone at the same time stays under Slack's rate limit |
| `SOLID_QUEUE_SHUTDOWN_TIMEOUT` | `5` | Seconds a stopping worker gives running jobs before putting them back on the queue. Keep it below your orchestrator's grace period. |
| `SLACK_SOCKET_MODE_READY_FILE` | _(unset)_ | A file `bin/slack-socket-mode` keeps fresh while it's connected to Slack, for readiness probes |
| `SOLID_QUEUE_IN_PUMA` | _(unset)_ | Set it to run background jobs inside the web process instead of a separate worker |
| `SOLID_QUEUE_SKIP_RECURRING` | _(unset)_ | Set it to `1` so the worker doesn't run the recurring schedule (scheduled standups, reminders, nightly cleanup). Useful locally to avoid DMing a real workspace. Works with `bin/jobs` and `SOLID_QUEUE_IN_PUMA`. |

### Production web settings

| Variable | Default | Description |
| --- | --- | --- |
| `APP_HOSTS` or `APP_HOST` | `app.example.com` | Comma-separated hostnames the app will respond to |
| `FORCE_SSL` | `true` | Redirect HTTP to HTTPS |
| `ASSUME_SSL` | Same as `FORCE_SSL` | Treat requests as HTTPS, for when SSL ends at a proxy |
| `RAILS_MASTER_KEY` | | Decrypts `config/credentials.yml.enc` |
| `RAILS_LOG_LEVEL` | `info` | Log verbosity |

## Standup YAML files

Besides the web console, you can define standups as YAML files in `config/standups/`. Here's an example:

```yaml
name: "Engineering Team Daily Standup"
platform: "slack"
platform_channel: "eng-standup"

schedule:
  timezone: "America/Los_Angeles"
  days: [monday, tuesday, wednesday, thursday, friday]
  time: "09:30"

intro: "Please share what you've been working on."
questions:
  - "What did you accomplish since the last standup?"
  - "What are you working on today?"
  - "Are there any blockers?"
outro: "Thanks! Have a productive day."

participants:
  - platform_user_id: "U01ABC123"
    name: "Sarah Thompson"
    active: true
  - platform_user_id: "U02DEF456"
    name: "Michael Chen"
    active: false # on vacation
```

`name`, `platform_channel`, and `questions` are required. `platform` is optional and defaults to `slack`. For a Teams standup, set `platform: "teams"`, use a `TEAM_ID|CHANNEL_ID` channel, and list participants by Entra object ID. A `days` list of Monday through Friday becomes a weekdays schedule, all seven days becomes daily, and anything else becomes a weekly schedule on those days. When `timezone` is set, each participant gets their DM at `time` in their own Slack timezone.

Check your files, then load them into the database:

```bash
bin/rails standups:validate   # also runs in CI
bin/rails standups:import     # creates or updates standups and participants
```

See [`config/standups/myteam.yml`](../config/standups/myteam.yml) for a full example.

## Accounts

Anyone can run a standup. It doesn't matter whether they're a manager on the org chart or leading a virtual team.

With [Sign in with Slack](slack-setup.md#sign-in-with-slack-optional) turned on, anyone in your workspace can sign in. They get an account automatically and can create standups right away.

Without Slack sign-in, people use an email and an access token. Only a SHA-256 digest of the token is stored, so save the raw token somewhere safe when you create it. Create these accounts in the Rails console:

```ruby
token = SecureRandom.hex(32)
User.create!(email: "lead@example.com", name: "Team Lead", role: "manager", access_token: token)
puts token # share this once with the manager
```

The same email and access token work as a bearer token for the [API](api.md), so scripts act as that person. Slack and Microsoft accounts get a random token nobody sees; to give one to someone for scripting, set a new one in the Rails console with `user.update!(access_token: SecureRandom.hex(32))`. That also signs out any script using their old token.

There are two roles:

- `manager` is the standard role. Whoever manages a standup can also make other people in it managers of that standup from the People tab. People with it can create standups and manage the ones they own. Any standup someone creates is theirs automatically.
- `admin` can manage every standup and can open the **Admin** page to check installation health and see every user. See [Architecture](architecture.md#web-console-personas-and-permissions) for more.
