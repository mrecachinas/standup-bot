# Getting started

There are three ways to run Standup Bot locally:

- **Docker Compose** runs the whole app in containers. It's the fastest way to try things out, and you don't need Ruby installed.
- **Native Rails** runs the app directly on your machine against MySQL. Use this when you're working on the code.
- **Dev Container** gives you the native Rails setup inside a container, with Ruby, Node, and MySQL already installed. Use this to work on the code without installing anything locally.

## Option 1: Docker Compose

```bash
docker compose up --build
```

This starts Postgres, prepares the databases, seeds an admin user, and runs both the web server (on <http://localhost:3000>) and the background job worker. The containers run with `RAILS_ENV=production`, so it behaves like a real deployment.

Sign in with the seeded admin:

- **Email:** `admin@example.com`
- **Access token:** `local-manager-token`

You don't need Slack or Teams credentials for this. Chat features in the console will tell you they're not configured until you [connect Slack or Teams](#connecting-slack-or-teams).

To use your own admin credentials (the token also works for the [API](api.md)):

```bash
MANAGER_ADMIN_EMAIL=you@example.com \
MANAGER_ADMIN_TOKEN=replace-with-a-long-random-token \
docker compose up --build
```

To stop, run `docker compose down`. To also wipe the database, run `docker compose down -v`.

### Connecting Slack or Teams

`docker-compose.yml` doesn't pass chat credentials into the containers. Once you've [created a Slack app](slack-setup.md) or [registered a Teams bot](teams-setup.md), add the credentials to the `environment` block under `x-app` so the web and worker containers both get them:

```yaml
    SLACK_BOT_TOKEN: ${SLACK_BOT_TOKEN:-}
    SLACK_SIGNING_SECRET: ${SLACK_SIGNING_SECRET:-}
    SLACK_CONNECTION_MODE: ${SLACK_CONNECTION_MODE:-http}
    SLACK_APP_TOKEN: ${SLACK_APP_TOKEN:-}
    TEAMS_APP_ID: ${TEAMS_APP_ID:-}
    TEAMS_APP_PASSWORD: ${TEAMS_APP_PASSWORD:-}
    TEAMS_TENANT_ID: ${TEAMS_TENANT_ID:-}
```

Then export the values in your shell and run `docker compose up` again. If you're using [Socket Mode](slack-setup.md#run-the-socket-mode-client), add `--profile slack-socket-mode` so Compose also starts the Slack connection. With native Rails (below), just set the environment variables before running `script/server` and `bin/jobs`.

## Option 2: Native Rails with MySQL

### Prerequisites

- Ruby (the version in [`.ruby-version`](../.ruby-version))
- Node (the version in [`.node-version`](../.node-version)) for the web console
- MySQL 8, or Docker so the scripts can start MySQL for you

### Run it

```bash
script/bootstrap   # install gems and the console's npm packages
script/server      # start MySQL if needed, prepare and seed the database, start Rails and the console
```

Open <http://localhost:5173>. `script/server` seeds the same `admin@example.com` / `local-manager-token` admin as Docker Compose, and the sign-in form is pre-filled in development.

Rails handles web requests, but scheduling, sending DMs, and posting summaries all happen in background jobs. To run them, start the job worker in a second terminal:

```bash
bin/jobs
```

If you'd rather set things up by hand, `bin/setup` installs gems and npm packages, prepares the database, and starts `bin/dev`. You can also run `bundle install`, `(cd frontend && npm ci)`, `bin/rails db:prepare`, and `bin/dev` yourself. See [Development](development.md#running-the-app) for more on `bin/dev`.

### Database settings

By default, development and test connect to MySQL on `127.0.0.1:3306` as `root` with no password. You can override this with `DB_HOST`, `DB_PORT`, `DB_USER`, and `DB_PASSWORD`. The `docker-compose.yml` file has a `mysql` service that matches these defaults:

```bash
docker compose up -d --wait mysql
```

## Option 3: Dev Container

Open the repository in VS Code and choose **Dev Containers: Reopen in Container**. The [`.devcontainer`](../.devcontainer) setup also works with the [`devcontainer` CLI](https://github.com/devcontainers/cli). It builds a Ruby and Node container alongside a MySQL 8 container, then runs `bin/setup --skip-server` to install gems and npm packages and prepare the databases.

Once it's up, use the same commands as native Rails from a terminal inside the container: `script/server`, `bin/jobs`, `script/test`, and so on. VS Code forwards the console on port 5173 and Rails on port 3000. For the end-to-end tests, run `npx playwright install --with-deps chromium` in `frontend/` once.

## Next steps

- [Connect the bot to Slack](slack-setup.md)
- [Define standups in YAML](configuration.md#standup-yaml-files) or create them in the web console
- [Run the tests](development.md)
