# Copilot Instructions for Standup Bot

## Project Overview

This is a Ruby on Rails 8.0.2 application that serves as a Slack standup bot. The bot facilitates scheduled standup meetings by asking participants questions and collecting their responses in Slack channels.

## Tech Stack

- **Ruby**: 3.4.2
- **Rails**: 8.0.2
- **Database**: SQLite (with plans for MySQL/PostgreSQL in production)
- **Background Jobs**: Solid Queue
- **Cache**: Solid Cache
- **WebSockets**: Solid Cable
- **Testing**: Minitest with Mocha for mocking
- **Linting**: RuboCop with Rails Omakase configuration
- **Security**: Brakeman static analysis
- **Deployment**: Kamal (Docker-based)
- **Slack Integration**: slack-ruby-client gem

## Architecture

### Models
- `Standup`: Core model representing a standup configuration with schedule, questions, and channel info
- `StandupParticipant`: Junction model for users participating in standups
- `StandupResponse`: Tracks individual user responses to standup questions

### Services
- `SlackClient`: Wrapper for Slack API interactions
- `SlackCommands`: Handles Slack slash commands
- `SlackSignatureVerifier`: Verifies Slack webhook signatures for security
- `StandupResponseService`: Core business logic for processing standup responses

### Controllers
- `SlackEventsController`: Handles incoming Slack webhooks and events

### Formatters
- `StandupFormatter`: Formats standup questions and responses for Slack

## Development Workflow

### Setting up Development Environment
```bash
# Install dependencies
bundle install

# Setup database
bin/rails db:create db:migrate

# Run tests
bin/rails test

# Run linting
bin/rubocop

# Run security scan
bin/brakeman --no-pager
```

### Running the Application
```bash
# Development server
bin/rails server

# Console
bin/rails console

# Background jobs (if needed separately)
bin/jobs
```

## Testing Conventions

### Test Structure
- Use Minitest as the testing framework
- Tests are organized in `test/` directory matching the `app/` structure
- Use fixtures in `test/fixtures/` for test data
- Tests run in parallel using multiple processors

### Mocking and Stubbing
- Use Mocha for mocking external dependencies (especially Slack API calls)
- Mock the `SlackClient` service in tests to avoid actual API calls
- Use `Timecop` for time-based testing (freezing time for schedule testing)

### Test Examples
```ruby
# Testing service objects
class StandupResponseServiceTest < ActiveSupport::TestCase
  def setup
    @mock_slack_client = mock('SlackClient')
    StandupResponseService.stubs(:slack_client).returns(@mock_slack_client)
  end

  test "should process answer correctly" do
    @mock_slack_client.expects(:send_message).once
    # Test implementation
  end
end

# Testing models with time
test "should calculate next occurrence for daily standup" do
  Timecop.freeze(Time.new(2025, 4, 6, 8, 0, 0, "+00:00")) do
    # Test time-dependent logic
  end
end
```

## Code Style and Conventions

### Ruby Style
- Follow Rails Omakase Ruby styling (configured via RuboCop)
- Use explicit configuration: `bin/rubocop --config .rubocop.yml`
- No additional custom rules beyond Omakase defaults

### Rails Conventions
- Use service objects for complex business logic
- Keep controllers thin - delegate to services
- Use ActiveRecord callbacks judiciously
- Prefer explicit over implicit behavior

### Naming Conventions
- Service classes end with `Service`
- Use descriptive method names
- Follow Rails naming conventions for models, controllers, etc.

## CI/CD Pipeline

### GitHub Actions Workflow (`.github/workflows/ci.yml`)
The CI pipeline runs three parallel jobs:

1. **Security Scanning** (`scan_ruby`):
   ```bash
   bin/brakeman --no-pager
   ```

2. **Linting** (`lint`):
   ```bash
   bin/rubocop -f github
   ```

3. **Testing** (`test`):
   ```bash
   bin/rails db:test:prepare test
   ```

### Pre-commit Checks
Before making commits, ensure:
- Tests pass: `bin/rails test`
- Linting passes: `bin/rubocop`
- Security scan passes: `bin/brakeman --no-pager`

## Deployment

### Kamal Configuration
- Uses Docker for containerization
- Configuration in `config/deploy.yml`
- Supports multiple environments (development, production)
- SSL termination with Let's Encrypt
- Uses secrets management for sensitive data

### Deployment Commands
```bash
# Deploy to production
bin/kamal deploy

# Check deployment status
bin/kamal app logs

# Run console on production
bin/kamal console

# Database console
bin/kamal dbc
```

### Pre-deployment Hooks
- `.kamal/hooks/pre-build.sample`: Validates git state and branch synchronization
- `.kamal/hooks/pre-deploy.sample`: Checks GitHub CI status before deployment

## Slack Integration

### Authentication
- Uses Slack app credentials and signing secrets
- Webhook signature verification for security
- OAuth tokens for API access

### Message Formatting
- Use Slack's Block Kit for rich message formatting
- Markdown formatting for text (`*bold*`, `_italic_`)
- Handle special characters in questions and responses

### API Interactions
- Always mock Slack API calls in tests
- Handle rate limiting and retries
- Verify webhook signatures for security

## Database Schema

### Key Tables
- `standups`: Main configuration table with JSON fields for questions and schedule
- `standup_participants`: Junction table for user participation
- `standup_responses`: Stores user responses with JSON answers array

### Migrations
- Use Rails migrations for schema changes
- Include default values and null constraints
- Use JSON columns for flexible data storage (questions, schedule configuration)

## Background Jobs

### Solid Queue
- Jobs run in-process with Puma by default (`SOLID_QUEUE_IN_PUMA=true`)
- Use Active Job for scheduling standup reminders
- Handle timezone-aware scheduling

## Environment Configuration

### Development
- SQLite database
- Local file storage for Active Storage
- Detailed error pages enabled

### Test
- In-memory or test database
- Parallel test execution
- Mock external services

### Production
- Environment-specific database configuration
- SSL enforcement
- Background job processing
- Proper error handling and logging

## Dependencies Management

### Dependabot
- Automatic dependency updates configured
- Updates both Ruby gems and GitHub Actions
- Daily update schedule

### Key Dependencies
- `slack-ruby-client`: Slack API integration
- `kamal`: Deployment tool
- `solid_*`: Modern Rails stack (queue, cache, cable)
- `rubocop-rails-omakase`: Code styling
- `brakeman`: Security scanning
- `mocha`: Test mocking
- `timecop`: Time testing utilities

## Common Patterns

### Service Object Pattern
```ruby
class MyService
  def self.call(*args)
    new(*args).call
  end

  def initialize(param)
    @param = param
  end

  def call
    # Implementation
  end

  private

  # Private methods
end
```

### Error Handling
- Use Rails error handling conventions
- Log errors appropriately for debugging
- Return appropriate HTTP status codes
- Handle Slack API errors gracefully

### Configuration
- Use Rails credentials for secrets
- Environment-specific configuration in `config/environments/`
- Use environment variables for deployment-specific settings

## Debugging

### Tools Available
- `pry` for interactive debugging
- Rails console for data exploration
- Detailed error pages in development
- Comprehensive logging

### Common Debug Scenarios
- Slack webhook delivery issues
- Timezone calculation problems
- Background job failures
- Database query optimization

## Performance Considerations

### Database
- Use appropriate indexes
- Consider query optimization for large datasets
- Use database-specific features when beneficial

### Slack API
- Handle rate limiting
- Batch operations when possible
- Cache user information appropriately

### Background Jobs
- Monitor job queue health
- Handle failures gracefully
- Use appropriate retry strategies