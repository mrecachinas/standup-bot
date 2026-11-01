# Copilot Instructions for Standup Bot

## Project Overview
Ruby on Rails 8.1 standup bot for Slack and Microsoft Teams that schedules meetings, asks participants questions, and collects responses in team channels. Each standup has a `platform`.

## Tech Stack
- **Ruby**: 4.0.2, **Rails**: 8.1.4
- **Database**: MySQL 8.0 in development/test (via docker compose), PostgreSQL in production
- **Background Jobs**: Solid Queue, **Cache**: Solid Cache, **WebSockets**: Solid Cable  
- **Testing**: Minitest with Mocha, **Linting**: RuboCop Rails Omakase, **Security**: Brakeman
- **Deployment**: Kamal, **Slack**: slack-ruby-client gem, **Teams**: Bot Connector + Microsoft Graph over Faraday, `jwt` for token validation

## Architecture

### Models
- `Standup`: Core model with schedule, questions, and channel configuration
- `StandupParticipant`: Junction model for user participation
- `StandupResponse`: Tracks user responses to standup questions

### Services  
- `ChatPlatform`: Adapter registry. Shared code calls `ChatPlatform.for_standup(standup)` (or `ChatPlatform.for(:slack)`) and the `ChatPlatform::Adapter` contract, never a platform SDK
- `ChatPlatform::SlackAdapter`: Slack implementation (Block Kit and mrkdwn live here); `SlackClient` is the low-level Slack API wrapper underneath it
- `ChatPlatform::TeamsAdapter`: Teams implementation on `Microsoft::BotConnectorClient` and `Microsoft::GraphClient`; people are Entra object IDs, channels are `TEAM_ID|CHANNEL_ID`
- `ChatIntegrationService.for(platform)`: Console credential checks and discovery (`SlackIntegrationService`, `TeamsIntegrationService`)
- `StandupConversationHandler` / `DirectMessageCommands`: Platform-neutral DM handling (answers, edits, `skip`/`away`/...)
- `StandupCommandHandler`: Platform-neutral `/standup` commands, returning `ChatPlatform::Reply` objects
- `SlackSignatureVerifier`: Webhook signature verification
- `StandupResponseService`: Core business logic for responses

### Controllers & Formatters
- `SlackEventsController`: Handles Slack webhooks/events
- `TeamsActivitiesController`: Verifies Bot Framework JWTs and queues `TeamsActivityProcessorJob`
- `StandupFormatter`: Formats questions using the adapter's formatter

## Development

### Setup & Common Commands
```bash
script/bootstrap            # Install dependencies
script/server               # Start MySQL (via docker compose) + rails server
script/test                 # Start MySQL (via docker compose) + run tests
script/test test/models/    # Run a specific test file or directory
bin/rails db:create db:migrate
bin/rubocop && bin/brakeman --no-pager
bin/rails standups:validate # Validate config/standups/*.yml
```

### CI/CD Pipeline
- **Security**: `bin/brakeman --no-pager`
- **Linting**: `bin/rubocop -f github`
- **Config validation**: `bin/rails standups:validate`
- **Testing**: `bin/rails db:test:prepare test` (MySQL service container in CI)

## Testing & Code Style

### Testing Conventions
- **Framework**: Minitest with fixtures in `test/fixtures/`
- **Mocking**: Use Mocha for external dependencies (especially Slack API)
- **Time Testing**: Use `Timecop` for schedule/time-dependent tests
- **Pattern**: Always mock `SlackClient.instance` (beneath the Slack adapter) or the adapter itself to avoid real API calls. New adapters include `test/support/chat_platform_adapter_contract.rb`; Teams tests use `test/support/teams_test_helper.rb` (`enable_teams!`)
- **Rake tasks**: Use `capture_io` to suppress puts output in tests

### Code Style
- **Ruby**: Rails Omakase styling via RuboCop (`.rubocop.yml`)
- **Services**: Plain Ruby objects in `app/services`; there is no single naming or call convention, so match neighboring code
- **Controllers**: Keep thin, delegate to services
- **Naming**: Follow Rails conventions, use descriptive method names

## Slack Integration

### Authentication & Security
- Uses Slack app credentials and signing secrets
- Webhook signature verification via `SlackSignatureVerifier`
- OAuth tokens for API access

### Message Formatting & API
- **Formatting**: Slack Block Kit for rich messages, Markdown (`*bold*`, `_italic_`)
- **Testing**: Always mock Slack API calls, handle rate limiting
- **Pattern**: Verify webhook signatures, handle special characters in responses

## Database & Background Jobs

### MySQL Conventions
- **No defaults on TEXT/JSON columns** — MySQL doesn't allow them. Use `attribute` declarations in models instead:
  ```ruby
  attribute :questions, :json, default: -> { [] }
  attribute :intro, :text, default: "Hello!"
  ```
- **JSON columns**: Use `t.json` in migrations (no `default:` or `null: false`), set defaults via model `attribute` API

### Schema
- **Key Tables**: `standups` (configuration, JSON questions/schedule), `standup_participants` (junction), `standup_responses` (JSON answers)
- **Migrations**: Use Rails migrations. Avoid DB-level defaults on TEXT/JSON columns.

### Solid Queue  
- Jobs run as a separate deployment (`bin/jobs`), decoupled from Puma
- Use Active Job for scheduling standup reminders
- Handle timezone-aware scheduling
- Retry strategy in `ApplicationJob`: exponential backoff for Slack rate limits and network errors

### Standup Config Files
- YAML config files live in `config/standups/*.yml`
- Validate with `bin/rails standups:validate` (runs in CI)
- Import with `bin/rails standups:import`

## Common Patterns

### Error Handling
- Use Rails conventions, log appropriately, return proper HTTP status codes
- Handle Slack API errors gracefully

### Configuration
- Rails credentials for secrets
- Environment variables for deployment settings (`DB_HOST`, `DB_USER`, `DB_PASSWORD`, etc.)
- Environment-specific config in `config/environments/`
- Standup definitions in `config/standups/*.yml`