# Configuration

Standup Bot is configured with environment variables. You can set up standups themselves in the web console or in YAML files.

## Environment variables

### Slack

| Variable | Required | Description |
| --- | --- | --- |
| `SLACK_BOT_TOKEN` | Yes, to use Slack | Bot User OAuth Token (`xoxb-…`) |
| `SLACK_SIGNING_SECRET` | Yes, to use Slack | Used to verify that requests really come from Slack |
| `SLACK_CLIENT_ID` | No | Slack app client ID |
| `SLACK_CLIENT_SECRET` | No | Slack app client secret |

See [Slack setup](slack-setup.md) for where to find these.

### Access

| Variable | Description |
| --- | --- |
| `ADMIN_API_TOKEN` | Bearer token for the [`/api/*` endpoints](api.md). It can also be stored in Rails credentials as `admin.api_token`. |
| `MANAGER_ADMIN_EMAIL`, `MANAGER_ADMIN_TOKEN`, `MANAGER_ADMIN_NAME` | When the email and token are both set, `bin/rails db:seed` creates or updates an admin user for the web console. |

### Database

In production, the app uses PostgreSQL with four databases: the main one, plus separate ones for the Solid Cache, Solid Queue, and Solid Cable stores.

| Variable | Description |
| --- | --- |
| `DATABASE_URL` | Main database |
| `CACHE_DATABASE_URL`, `QUEUE_DATABASE_URL`, `CABLE_DATABASE_URL` | The cache, queue, and cable databases |
| `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` | An alternative to `DATABASE_URL`. These also set the MySQL connection in development and test. |

Each of the cache, queue, and cable databases also accepts `CACHE_DB_*`, `QUEUE_DB_*`, and `CABLE_DB_*` overrides. Anything you don't set falls back to the matching `DB_*` value.

### Operations

| Variable | Default | Description |
| --- | --- | --- |
| `ADMIN_CHANNEL` | _(unset)_ | Slack channel that gets a message when a background job fails |
| `RESPONSE_RETENTION_DAYS` | `90` | How long to keep standup responses |
| `STALE_PENDING_DAYS` | `7` | When unanswered standups are marked expired |
| `CLEANUP_BATCH_SIZE` | `1000` | Rows per batch in the nightly cleanup job |
| `JOB_CONCURRENCY` | `1` | Number of job worker processes |
| `SOLID_QUEUE_IN_PUMA` | _(unset)_ | Set it to run background jobs inside the web process instead of a separate worker |

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
slack_channel: "eng-standup"

schedule:
  timezone: "America/Los_Angeles"
  days: [monday, tuesday, wednesday, thursday, friday]
  time: "09:30"

intro: "Good morning! Please answer these questions for today's standup:"
questions:
  - "What did you accomplish since the last standup?"
  - "What are you working on today?"
  - "Are there any blockers?"
outro: "Thanks! Have a productive day."

participants:
  - slack_id: "U01ABC123"
    name: "Sarah Thompson"
    active: true
  - slack_id: "U02DEF456"
    name: "Michael Chen"
    active: false # on vacation
```

`name`, `slack_channel`, and `questions` are required. A `days` list of Monday through Friday becomes a weekdays schedule, all seven days becomes daily, and anything else becomes a weekly schedule on those days. When `timezone` is set, each participant gets their DM at `time` in their own Slack timezone.

Check your files, then load them into the database:

```bash
bin/rails standups:validate   # also runs in CI
bin/rails standups:import     # creates or updates standups and participants
```

See [`config/standups/myteam.yml`](../config/standups/myteam.yml) for a full example.

## Manager accounts

People sign in to the web console with an email and an access token. Only a SHA-256 digest of the token is stored, so save the raw token somewhere safe when you create it. There's no UI for creating users yet, so use the Rails console:

```ruby
token = SecureRandom.hex(32)
User.create!(email: "lead@example.com", name: "Team Lead", role: "manager", access_token: token)
puts token # share this once with the manager
```

Admins can manage every standup and can open the **Admin** page to check installation health and see every user. Managers can only manage standups they own, and any standup a manager creates is theirs automatically. See [Architecture](architecture.md#manager-console-and-permissions) for more.
