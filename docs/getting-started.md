# Getting started

There are two ways to run Standup Bot locally:

- **Docker Compose** runs the whole app in containers. It's the fastest way to try things out, and you don't need Ruby installed.
- **Native Rails** runs the app directly on your machine against MySQL. Use this when you're working on the code.

## Option 1: Docker Compose

```bash
docker compose up --build
```

This starts Postgres, prepares the databases, seeds an admin user, and runs both the web server (on <http://localhost:3000>) and the background job worker. The containers run with `RAILS_ENV=production`, so it behaves like a real deployment.

Sign in with the seeded admin:

- **Email:** `admin@example.com`
- **Access token:** `local-manager-token`

You don't need Slack or Teams credentials for this. Chat features in the console will tell you they're not configured until you [connect Slack or Teams](#connecting-slack-or-teams).

To use your own admin credentials and API token:

```bash
MANAGER_ADMIN_EMAIL=you@example.com \
MANAGER_ADMIN_TOKEN=replace-with-a-long-random-token \
ADMIN_API_TOKEN=replace-with-a-long-random-token \
docker compose up --build
```

To stop, run `docker compose down`. To also wipe the database, run `docker compose down -v`.

### Connecting Slack or Teams

`docker-compose.yml` doesn't pass chat credentials into the containers. Once you've [created a Slack app](slack-setup.md) or [registered a Teams bot](teams-setup.md), add the credentials to the `environment` block under `x-app` so the web and worker containers both get them:

```yaml
    SLACK_BOT_TOKEN: ${SLACK_BOT_TOKEN:-}
    SLACK_SIGNING_SECRET: ${SLACK_SIGNING_SECRET:-}
    TEAMS_APP_ID: ${TEAMS_APP_ID:-}
    TEAMS_APP_PASSWORD: ${TEAMS_APP_PASSWORD:-}
    TEAMS_TENANT_ID: ${TEAMS_TENANT_ID:-}
```

Then export the values in your shell and run `docker compose up` again. With native Rails (below), just set the environment variables before running `script/server` and `bin/jobs`.

## Option 2: Native Rails with MySQL

### Prerequisites

- Ruby (the version in [`.ruby-version`](../.ruby-version))
- MySQL 8, or Docker so the scripts can start MySQL for you

### Run it

```bash
script/bootstrap   # install gems
script/server      # start MySQL if needed, prepare and seed the database, start Rails
```

`script/server` seeds the same `admin@example.com` / `local-manager-token` admin as Docker Compose, and the sign-in form is pre-filled in development.

Rails handles web requests, but scheduling, sending DMs, and posting summaries all happen in background jobs. To run them, start the job worker in a second terminal:

```bash
bin/jobs
```

If you'd rather set things up by hand, `bin/setup` installs gems, prepares the database, and starts the server. You can also run `bundle install`, `bin/rails db:prepare`, and `bin/rails server` yourself.

### Database settings

By default, development and test connect to MySQL on `127.0.0.1:3306` as `root` with no password. You can override this with `DB_HOST`, `DB_PORT`, `DB_USER`, and `DB_PASSWORD`. The `docker-compose.yml` file has a `mysql` service that matches these defaults:

```bash
docker compose up -d --wait mysql
```

## Next steps

- [Connect the bot to Slack](slack-setup.md)
- [Define standups in YAML](configuration.md#standup-yaml-files) or create them in the web console
- [Run the tests](development.md)
