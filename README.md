# Standup Bot

A Slack bot that automates daily standup meetings by scheduling personalized questions for team members and collecting responses in a shared channel.

## Features

- **Automated Scheduling**: Send standup questions to team members at their preferred times
- **Timezone Support**: Respects individual timezone preferences for standup delivery
- **Flexible Configuration**: Supports daily, weekdays, weekly, and custom schedules
- **Interactive Responses**: Collects responses through Slack DMs and posts summaries to team channels
- **Team Management**: Add/remove participants and manage multiple standup configurations
- **Admin API**: Manage standups, participants, responses, stats, and analytics with bearer-token auth
- **Observability**: Health checks, operational metrics, structured standup events, and job failure notifications
- **Data Retention**: Scheduled cleanup for old responses and stale pending standups

## Architecture

This is a Ruby on Rails 8.0 API-only application that integrates with Slack's Web API and Events API.

### Core Components

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Slack API     │◄──►│   Rails App      │◄──►│ MySQL/Postgres  │
│                 │    │                  │    │                 │
│ • Events API    │    │ • Controllers    │    │ • Standups      │
│ • Web API       │    │ • Jobs           │    │ • Participants  │
│ • Bot Token     │    │ • Services       │    │ • Responses     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

### Key Models

- **Standup**: Configuration for a team's standup (questions, schedule, participants)
- **StandupParticipant**: Links users to standups with timezone preferences
- **StandupResponse**: Stores user responses to standup questions
- **User**: Manager/admin web identity authenticated with an access token
- **StandupOwnership**: Assigns managers to the standups they can manage
- **AuditLog**: Records manager/admin changes to standups and participants

### Manager Web UI Authorization

The browser UI uses cookie-backed sessions and `User` records. Users have either the `admin` or `manager` role. Admins can manage every standup; managers can only manage standups linked through `StandupOwnership`. New manager-created standups automatically become owned by that manager. Use `Standup.manageable_by(user)`, `standup.manageable_by?(user)`, or `user.can_manage_standup?(standup)` in future UI controllers.

`User#access_token=` stores only a SHA-256 digest, so provision high-entropy tokens and show the raw token only once. The existing `ADMIN_API_TOKEN` still protects `/api/*` endpoints as a global admin API credential. Manager/admin create, update, and delete actions should call `AuditLogger.log!` (or the controller helpers) so changes are captured in `AuditLog`.

### Background Jobs

- **SchedulingJob**: Processes active standups and schedules messages
- **StandupMessageJob**: Sends initial standup questions to users
- **SlackEventProcessorJob**: Handles incoming Slack events and responses
- **DataCleanupJob**: Expires stale pending responses and deletes data beyond the retention window

## Configuration

### Environment Variables

Create a `.env` file or set these environment variables:

```bash
# Required Slack API credentials
SLACK_BOT_TOKEN=xoxb-your-bot-token-here
SLACK_SIGNING_SECRET=your-signing-secret-here
SLACK_CLIENT_ID=your-client-id-here
SLACK_CLIENT_SECRET=your-client-secret-here

# Production database configuration (PostgreSQL by default)
DATABASE_URL=postgres://nerdbot:password@db/nerdbot_production

# Admin API bearer token. Required for /api/* endpoints.
ADMIN_API_TOKEN=replace-with-a-long-random-token

# Optional operational notifications and retention tuning
ADMIN_CHANNEL=C1234567890
RESPONSE_RETENTION_DAYS=90
STALE_PENDING_DAYS=7
CLEANUP_BATCH_SIZE=1000

# Optional: Rails configuration
RAILS_ENV=production
RAILS_MASTER_KEY=your-master-key-here
```

### Example Standup Configuration

Create standup configurations in `config/standups/your-team.yml`:

```yaml
name: "Engineering Team Daily Standup"
slack_channel: "eng-standup"
schedule:
  timezone: "America/Los_Angeles"
  days:
    - monday
    - tuesday
    - wednesday
    - thursday
    - friday
  time: "09:30"
  
intro: "Good morning! Let's check in on your progress. Please answer these questions for today's standup:"

questions:
  - "What did you accomplish since the last standup?"
  - "What are you working on today?"
  - "Are there any blockers or challenges you're facing?"
  - "Do you need help from anyone on the team?"

outro: "Thanks for completing your standup! Have a productive day."

participants:
  - slack_id: "U01ABC123"
    name: "Sarah Thompson"
    active: true
  - slack_id: "U02DEF456" 
    name: "Michael Chen"
    active: true
  - slack_id: "U03GHI789"
    name: "Priya Patel" 
    active: true
```

## Running the Application

### Prerequisites

- Ruby 3.4.2 (see `.ruby-version`)
- MySQL 8 for the default local/test configuration
- PostgreSQL 16 for production-style deployments
- Bundler gem

### Development Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/mrecachinas/standup-bot.git
   cd standup-bot
   ```

2. **Install dependencies and setup database**
    ```bash
    bin/setup
    ```
   This will:
   - Install Ruby gems with `bundle install`
   - Setup the database with `rails db:prepare`
    - Clear logs and temp files
    - Start the development server

3. **Docker Compose full app (without Slack)**
   ```bash
   docker compose up --build
   ```
   This starts Postgres, prepares the primary/cache/queue/cable databases, seeds a local admin, runs the Rails web process on http://localhost:3000, and runs the Solid Queue worker. Slack credentials are optional for this mode; Slack-related UI will report missing configuration until real credentials are provided.

   Default local manager UI credentials:
   - Email: `admin@example.com`
   - Access token: `local-manager-token`

   Override the seeded admin/API tokens when starting Compose:
   ```bash
   MANAGER_ADMIN_EMAIL=you@example.com \
   MANAGER_ADMIN_TOKEN=replace-with-a-long-random-token \
   ADMIN_API_TOKEN=replace-with-a-long-random-token \
   docker compose up --build
   ```

   Stop the app with `docker compose down`. To reset all Compose database data, run `docker compose down -v`.

4. **Manual setup (alternative)**
    ```bash
    bundle install
    rails db:create db:migrate
    rails server
    ```

5. **Run tests**
    ```bash
    bundle exec rails test
    ```

6. **Run with background jobs**
    ```bash
    # In one terminal
    rails server
   
   # In another terminal (for background job processing)
   bin/jobs
   ```

### Production Deployment

The application includes Docker and Kamal configuration for deployment:

1. **Using Docker**
   ```bash
   docker build -t standup-bot .
   docker run -d -p 80:80 -e RAILS_MASTER_KEY=<your-key> standup-bot
   ```

2. **Using Kamal**
   ```bash
   # Configure config/deploy.yml with your servers
   kamal setup
   kamal deploy
   ```

## Slack Integration Setup

### 1. Create a Slack App

1. Go to [Slack API](https://api.slack.com/apps)
2. Click "Create New App" → "From scratch"
3. Name your app (e.g., "Standup Bot") and select your workspace

You can also generate a Slack app manifest and create the app from that manifest:

```bash
APP_URL=https://your-domain.com bin/rails slack:manifest > slack-manifest.yml
```

For local Slack testing, expose Rails with ngrok or another tunnel first and use that public URL:

```bash
ngrok http 3000
APP_URL=https://abc123.ngrok-free.app bin/rails slack:manifest > slack-manifest.yml
```

In Slack, choose **Create New App** → **From an app manifest**, paste `slack-manifest.yml`, review, and create the app. The manifest configures the bot user, required scopes, event subscriptions, interactivity, and slash commands.

### 2. Configure Bot Permissions

Under **OAuth & Permissions**, add these Bot Token Scopes:
- `channels:read` - View basic information about public channels
- `chat:write` - Send messages as the bot
- `commands` - Register and receive slash commands
- `im:history` - Receive direct message events from users
- `im:write` - Start direct messages with people
- `users:read` - View people in the workspace

### 3. Configure Event Subscriptions

1. Go to **Event Subscriptions** and enable events
2. Set Request URL to: `https://your-domain.com/slack/events`
3. Subscribe to these bot events:
   - `message.im` - Listen to messages in direct messages

### 4. Install App to Workspace

1. Go to **Install App** and click "Install to Workspace"
2. Copy the **Bot User OAuth Token** (starts with `xoxb-`)
3. Copy the **Signing Secret** from **Basic Information**

### 5. Configure Slash Commands (Optional)

Create slash commands under **Slash Commands**:
- `/standup` - Trigger manual standup, status, skip, report, history, and help actions. Request URL: `https://your-domain.com/slack/commands/standup`
- `/standup-status` - Check standup status. Request URL: `https://your-domain.com/slack/commands/standup-status`

### 6. Test Your Integration

1. Set your environment variables with the tokens
2. Start your Rails server with a public URL (use ngrok for local testing)
3. Send a direct message to your bot
4. Check your Rails logs to see if events are being received

### Local Development with ngrok

```bash
# Install ngrok and expose your local server
ngrok http 3000

# Use the ngrok URL in your Slack app configuration
# e.g., https://abc123.ngrok.io/slack/events
```

## Usage

Once configured, the bot will:

1. **Schedule standups** based on your configuration files
2. **Send DMs** to participants at their scheduled times
3. **Collect responses** through conversational interface
4. **Post summaries** to the designated team channel
5. **Handle timezone differences** automatically

### Admin and Observability APIs

Admin routes require `Authorization: Bearer $ADMIN_API_TOKEN`.

```bash
curl -H "Authorization: Bearer $ADMIN_API_TOKEN" http://localhost:3000/api/standups
curl -H "Authorization: Bearer $ADMIN_API_TOKEN" http://localhost:3000/api/standups/1/stats
curl -H "Authorization: Bearer $ADMIN_API_TOKEN" http://localhost:3000/api/standups/1/analytics
```

Health endpoints are unauthenticated for load balancers and monitors:

```bash
curl http://localhost:3000/health
curl http://localhost:3000/health/detailed
curl http://localhost:3000/health/metrics
```

### Commands

Users can interact with the bot through:
- Direct messages for answering standup questions
- Slash commands (if configured)
- Mentions in channels

## Development

### Running Tests

```bash
# Run all tests
bundle exec rails test

# Run specific test files
bundle exec rails test test/models/standup_test.rb
bundle exec rails test test/services/slack_client_test.rb
```

### Code Style

The project uses RuboCop with Rails Omakase configuration:

```bash
# Check code style
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -A
```

### Security Scanning

```bash
# Run Brakeman security scanner
bundle exec brakeman
```

## Troubleshooting

### Common Issues

1. **Slack events not received**
   - Check your Request URL is publicly accessible
   - Verify the signing secret matches
   - Check Rails logs for verification errors

2. **Bot not responding to DMs**
   - Ensure `message.im` event subscription is active
   - Check bot has `im:write` permission
   - Verify bot is installed in the workspace

3. **Timezone issues**
   - Ensure participant timezone data is correct
   - Check system timezone settings
   - Verify Rails timezone configuration

### Logs

Check these log files for debugging:
- `log/development.log` - Application logs
- `log/production.log` - Production logs  
- Rails server output - Real-time request logs

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes with tests
4. Run the test suite
5. Submit a pull request

## License

This project is available as open source under the terms of the MIT License.
