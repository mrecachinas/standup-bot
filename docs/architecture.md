# Architecture

Standup Bot is a Rails 8 app. It's API-only: it serves Slack and Microsoft Teams webhooks and one JSON API under `/api`. The web console is a React single-page app (Primer React) that runs in the browser and talks to that same API. Background work runs on Solid Queue, and production data lives in PostgreSQL (development and test use MySQL).

## The big picture

```mermaid
flowchart LR
    subgraph Slack
        EV[Events API]
        SC[Slash commands]
        WEB[Web API]
    end

    subgraph Teams[Microsoft Teams]
        BF[Bot Connector]
        GR[Microsoft Graph]
    end

    subgraph App[Standup Bot]
        CTRL[Slack controllers]
        TCTRL[TeamsActivitiesController]
        SPA[SpaController<br/>serves the console]
        API[JSON API<br/>/api]
        JOBS[Background jobs<br/>Solid Queue]
    end

    DB[(PostgreSQL)]
    MGR([Browser: React console]) -->|session cookie| API
    MGR -.->|page loads| SPA
    OPS([Scripts / tools]) -->|bearer token| API

    EV --> CTRL
    SC --> CTRL
    BF --> TCTRL
    CTRL --> JOBS
    TCTRL --> JOBS
    JOBS --> WEB
    JOBS --> BF
    JOBS --> GR
    CTRL --> DB
    API --> DB
    JOBS --> DB
```

Requests from Slack are verified with the signing secret, and requests from Teams with the Bot Framework JWT (`Microsoft::BotFrameworkAuth`). Both are then handed off to background jobs, so the app can respond quickly.

Slack traffic can also arrive over [Socket Mode](slack-setup.md#run-the-socket-mode-client) (`SLACK_CONNECTION_MODE=socket`), where the app holds an outbound WebSocket instead of exposing request URLs. `SlackSocketMode::Client` (run by `bin/slack-socket-mode` or the `slack_socket_mode` Puma plugin) keeps the connection open, and `SlackSocketMode::Dispatcher` acks each envelope. Both transports call `SlackInbound`, so events, slash commands, and interactions behave the same either way:

```mermaid
flowchart LR
    HTTP[Slack controllers<br/>signing secret] --> IN[SlackInbound]
    WS[SlackSocketMode::Client<br/>app-level token] --> D[SlackSocketMode::Dispatcher] --> IN
    IN --> J[SlackEventProcessorJob]
    IN --> CMD[StandupCommandHandler]
```

## Chat platform adapters

Standup logic doesn't talk to Slack or Teams directly. Each standup has a `platform`, and everything goes through that platform's adapter, so Slack and Teams standups run side by side in one deployment.

```mermaid
flowchart LR
    SE[SlackEventsController] --> J[SlackEventProcessorJob]
    SS[SlackSlashCommandsController] --> CMD[StandupCommandHandler]
    TA[TeamsActivitiesController] --> TJ[TeamsActivityProcessorJob]
    J --> CH[StandupConversationHandler]
    TJ --> CH
    TJ --> CMD
    CH --> CMD
    CH --> SVC[StandupResponseService]
    CMD --> Jobs[Standup jobs]
    SVC --> REG["ChatPlatform.for_standup(standup)"]
    Jobs --> REG
    REG --> SA[ChatPlatform::SlackAdapter]
    REG --> TAD[ChatPlatform::TeamsAdapter]
    SA --> SC[SlackClient]
    TAD --> BC[Microsoft::BotConnectorClient]
    TAD --> GC[Microsoft::GraphClient]
```

- `ChatPlatform::Adapter` defines the contract: sending DMs and channel messages, posting and editing a person's update, posting reports, offering a choice of standups, looking up people and channels, validating IDs and channels, and a `formatter` for bold, italic, code, and channel references. Every adapter's tests include `test/support/chat_platform_adapter_contract.rb`.
- `ChatPlatform::SlackAdapter` implements it with Block Kit and mrkdwn on top of `SlackClient`, the low-level Web API wrapper.
- `ChatPlatform::TeamsAdapter` implements it with Teams markdown and Adaptive Cards. It uses the Bot Connector to message people and channels, and Microsoft Graph to look people and channels up. People are identified by Entra object ID, and channels by `TEAM_ID|CHANNEL_ID`. Before the bot can DM someone it needs a 1:1 conversation, which it opens (or learns about from incoming activities) and caches in `ChatConversation`. See [Microsoft Teams setup](teams-setup.md).
- Inbound messages are normalized into a `ChatPlatform::InboundMessage` and handled by `StandupConversationHandler`. Slash commands, Teams @mentions, and DM keywords (`help`, `skip`, `away`, ...) all go through `StandupCommandHandler`, which returns `ChatPlatform::Reply` objects that each platform renders its own way (`Adapter#send_reply`): ephemeral Block Kit in Slack, chat messages and cards in Teams.
- `ChatIntegrationService` (with `SlackIntegrationService` and `TeamsIntegrationService`) backs the console's credential checks, discovery, and test messages. `ChatUserResolver` turns what someone typed into a person on the standup's platform.

## A standup, end to end

```mermaid
sequenceDiagram
    participant Sched as SchedulingJob (hourly)
    participant Msg as StandupMessageJob
    participant User as Participant (Slack DM)
    participant Ctrl as SlackEventsController
    participant Proc as SlackEventProcessorJob
    participant Svc as StandupResponseService
    participant Post as StandupUpdateJob
    participant Chan as Team channel

    Sched->>Msg: queue a DM for each participant at their local time
    Msg->>User: intro + first question
    User->>Ctrl: reply (message.im event)
    Ctrl->>Proc: enqueue event
    Proc->>Svc: record answer (saved first)
    Svc->>User: next question
    Note over User,Svc: repeats until every question is answered
    Svc->>Post: post the update
    Post->>Chan: this person's update
    Post->>User: sign-off, and where it was posted
```

If someone doesn't reply, `StandupReminderJob` nudges them (by default once, after two hours, and both are configurable per standup). Once they've been silent for `STALE_PENDING_DAYS`, `DataCleanupJob` marks the response as expired. A participant can also type `skip`, `cancel`, or `away` instead of answering (see [DM commands](slack-setup.md#dm-commands)).

## Data model

```mermaid
erDiagram
    Standup ||--o{ StandupParticipant : has
    Standup ||--o{ StandupResponse : collects
    Standup ||--o{ StandupScheduleException : "skips / reschedules"
    Standup ||--o| ReportConfiguration : "reports via"
    Standup ||--o{ ReportGeneration : produces
    Standup ||--o{ StandupOwnership : "owned through"
    User ||--o{ StandupOwnership : owns
    User ||--o{ UserIdentity : "signs in as"
    ChatConversation }o--|| StandupParticipant : "DMs (Teams)"
    User ||--o{ AuditLog : "changes recorded in"
```

| Model | What it is |
| --- | --- |
| `Standup` | A team's standup: chat `platform`, channel, schedule, questions, intro/outro, and reminder settings. The platform is fixed once the standup exists |
| `StandupParticipant` | A person in a standup, identified by `platform_user_id` on the standup's platform, with their cached timezone and any vacation dates |
| `StandupResponse` | One person's answers for one standup date, with a status of `pending`, `completed`, `skipped`, `cancelled`, or `expired` |
| `StandupScheduleException` | A one-off change to the schedule: a skipped date, holiday, cancellation, or new time |
| `ReportConfiguration` / `ReportGeneration` | Where and how summary reports are delivered, plus a record of each one generated |
| `User` | A manager or admin who can sign in to the web console |
| `UserIdentity` | Links a `User` to their user ID on a chat platform, at most one per platform |
| `ChatConversation` | The bot's cached 1:1 conversation with a person, for platforms that need one before sending a DM (Teams) |
| `StandupOwnership` | Links managers to the standups they can manage |
| `AuditLog` | A record of changes managers and admins make |

The app doesn't use database foreign key constraints. Models own referential cleanup through `dependent:` options on their associations (for example, deleting a standup destroys its participants and reports, and deleting a user nullifies `actor_id` on their audit logs and report generations). A test checks that no foreign keys creep back into the app schema. Solid Queue's own tables keep the foreign keys that ship with the gem.

Schedules can be `daily`, `weekdays`, `weekly`, `biweekly`, `monthly`, or `custom`. You can also list holidays that apply to every standup in `config/holidays.yml`.

## Background jobs

| Job | When it runs | What it does |
| --- | --- | --- |
| `SchedulingJob` | Every hour | Finds standups due in the next window and queues a `StandupMessageJob` for each participant at their local time |
| `StandupMessageJob` | When queued | Opens the DM and sends the intro and first question, with a "Not today?" menu on Slack |
| `SlackEventProcessorJob` | On each Slack event (`inbound` queue) | Handles DM commands and records answers. Each answer keeps the ID of the message it came from, so editing that message updates the right answer (and its channel post) |
| `SlackInteractionJob` | On each Slack button or menu click in Socket Mode (`inbound` queue) | Handles the click and replies through its `response_url` |
| `TeamsActivityProcessorJob` | On each Teams activity (`inbound` queue) | The same for Teams, plus `standup` commands and card choices. It also caches the 1:1 conversation |
| `StandupPromptJob` | After each answer is saved (`inbound` queue) | Sends the next question, unless the run has moved on. Retries on rate limits and network errors |
| `StandupUpdateJob` | When a run finishes or an answer is edited | Posts (or updates) the person's update in the channel, then sends the sign-off. Retries on rate limits and network errors |
| `StandupUpdateSweepJob` | Every 15 minutes | Finishes runs whose update or sign-off never went out (say, a worker stopped right after the last answer was saved) |
| `StandupReminderJob` | Every 15 minutes | Reminds people who haven't finished, counting from the latest question, based on each standup's reminder settings. On Slack, it first checks the DM for replies the bot missed |
| `SlackDmBackfillJob` | When Socket Mode reconnects after an outage, or `bin/rails slack:backfill_dms` | Picks up replies sent while no connection was up, from DM history |
| `StandupCollectionJob` | On demand | Gathers completed responses into a report (for `/standup report` or the console) |
| `ParticipantReactivationJob` | At the start of the day after someone's last day away, in their timezone | Puts the participant back in rotation. If their away date has since moved later, it runs again after the new date |
| `DataCleanupJob` | Daily at 3am | Expires stale pending responses and deletes data older than the retention window |

Recurring schedules are defined in [`config/recurring.yml`](../config/recurring.yml). If you set `ADMIN_CHANNEL` (Slack) or `TEAMS_ADMIN_CHANNEL` (Teams), failed jobs post a message there, at most once per kind of failure every 15 minutes.

## Reliability

Chat platforms deliver events at least once, people type faster than the bot replies, and processes stop mid-job. The app is built so that none of these loses an answer or records it twice:

- **Each message is handled once.** Slack resends events it doesn't hear back about within 3 seconds (right away, then after a minute and five minutes), and Teams can too. `ProcessedChatMessage.process_once` records each message's ID (or a click's action timestamp) in the same transaction as whatever handling it saves, so a redelivery is skipped, and a failure leaves the message unhandled for the retry. Events and clicks are acknowledged only after they're queued.
- **One person's messages are handled one at a time, in order.** Inbound jobs share a Solid Queue concurrency key per person, on their own `inbound` queue, so quick replies can't overwrite each other and never wait behind a burst of scheduled sends. Answers are also saved under a row lock.
- **Messages typed before the next question showed up continue the previous answer.** Each run records when the bot's latest prompt reached the person (`prompted_at`, by Slack's clock), and each answer when its question was asked. If someone sends "foo" and then "bar" before the next question arrives, both are the first answer, even if "bar" is delivered late. Until a finished run's sign-off goes out, follow-ups belong to the last answer. Each message is kept as a part of the answer, so editing one changes just that part. `skip` is the exception: it skips the question coming next.
- **Answers are saved before anything is sent.** The next question (`StandupPromptJob`) and the channel post (`StandupUpdateJob`) go out only after the answer has committed, and retry on their own if Slack is unavailable, so a failed send can't undo an answer. Posts are made under the run's row lock from the saved answers. The person is told it was posted only once it has been. If the channel can't be posted to (the bot isn't in it, or it's archived), they're told their answers are saved, and the admins are notified. `StandupUpdateSweepJob` finishes any run whose post or sign-off was never sent.
- **Sends are paced.** When a standup goes out to everyone at once, `StandupMessageJob` sends `STANDUP_SEND_CONCURRENCY` first messages at a time, since Slack allows a workspace several hundred messages a minute. Names come from the stored participant rather than a profile lookup per message. A run is created only once its first message is out, so a reply can't land in a run the person hasn't seen.
- **Missed replies are recovered.** If no Socket Mode connection was up for longer than Slack keeps redelivering, the first client to reconnect queues `SlackDmBackfillJob`, which reads pending runs' full DM history since they started and replays missed replies into that run. Reminders check history the same way first. Messages already handled, or recorded in any of the person's runs, are skipped. Reminders are claimed before they're sent and counted only once delivered.

See [Kubernetes](deployment.md#kubernetes) for how this plays out across rolling deploys.

## Observability

Errors and events go through Rails' own reporters, `Rails.error` and `Rails.event`. Backends subscribe to them, so adding an error tracker or a metrics library means subscribing it, not changing app code. The built-in backends live in [`lib/instrumentation/`](../lib/instrumentation/) and are subscribed by `config/initializers/instrumentation.rb`.

```mermaid
flowchart LR
    subgraph App
        REQ[Requests and jobs<br/>unhandled errors]
        RESC[Rescued errors<br/>Rails.error.report]
        TRK[StandupMetrics.track / .measure]
        FW[Rails request and job events]
    end

    ERR{{Rails.error}}
    EVT{{Rails.event}}

    REQ --> ERR
    RESC --> ERR
    TRK --> EVT
    FW --> EVT

    ERR --> ELOG[ErrorLogSubscriber<br/>JSON log line]
    EVT --> LOG[LogSubscriber<br/>JSON log line]
    ERR --> STATSD[StatsdSubscriber<br/>if STATSD_ADDR is set]
    EVT --> STATSD
    ERR -.-> MORE[Your error tracker<br/>Rails.error.subscribe]
    EVT -.-> MORE2[Your metrics backend<br/>Rails.event.subscribe]
```

- **Errors.** Rails reports errors that escape a request by itself. `ApplicationJob` reports a job's failure (once `retry_on` gives up, or when nothing handles it) while the job's context is still set, so the report carries its `job_class` and `job_id`. Code that rescues an error and carries on reports it with `Rails.error.report(error, context: {...}, source: "...")`. Reporting the same exception twice is a no-op, so it's safe to report at the rescue and let it bubble up. By default each report becomes a structured log line with the class, message, a cleaned backtrace, and the context (filtered by `filter_parameters`).
- **Events.** `StandupMetrics.track("standup.sent", standup_id: 1)` reports an app event, and `StandupMetrics.measure("slack.api_request", operation: "send_message") { ... }` reports one with its `duration_ms` and `outcome`. Every Slack and Microsoft API call is measured this way. Keep payloads to IDs, counts, and error classes, never message text or error messages. Rails masks any payload key containing a `filter_parameters` word, so a count named `messages_scheduled` would log as `[FILTERED]`; call it `dms_scheduled`. `track` also records when each event was last seen, which `/health/detailed` and the admin dashboard show.
- **Metrics.** With `STATSD_ADDR` set, `StatsdSubscriber` sends DogStatsD counters and timings: one counter per app event, timings for measured events, `http.request` and `job.perform` timings from Rails' own events, job retries, and an `error` counter. Only low-cardinality payload keys (such as `operation`, `job_class`, `error_class`, `status`) become tags.
- **Logs.** Production logs one JSON object per line (`LOG_FORMAT=text` turns this off). Every line in a request carries its `request_id`, plus `user_id` or `member` for console and API requests; every line in a job carries `job_class`, `job_id`, and `queue`, and a job run inside another with `perform_now` puts the outer job's context back when it finishes. `Instrumentation.set_context` adds more for the rest of the request or job. Lograge writes one line per request.

To plug in another backend, subscribe it in an initializer. An error subscriber implements `report(error, handled:, severity:, context:, source:)`; an event subscriber implements `emit(event)`, where `event` is a Hash with `:name`, `:payload`, `:tags`, `:context`, and `:timestamp`:

```ruby
# config/initializers/error_tracker.rb
Rails.error.subscribe(MyErrorTracker::RailsSubscriber.new)
Rails.event.subscribe(MyMetrics::EventSubscriber.new) { |event| event[:name].start_with?("standup.") }
```

## Web console, personas, and permissions

The web console uses cookie-backed sessions and serves three kinds of people:

- **Admins** (`User` with role `admin`) can manage every standup.
- **Standup owners** (`User` with the standard `manager` role) manage the standups linked to them through `StandupOwnership`. Anyone can create a standup, for example to run one for a virtual team, and owns the standups they create. Being an owner has nothing to do with the org chart.
- **Members** are the people in standups. A member is identified by their platform and user ID on it, and the same person can be a `StandupParticipant` in several standups. `Member` (in `app/models/member.rb`) gathers those rows together.

"Sign in with Slack" (`SlackSessionsController` and `SlackSignIn`) uses Slack's OpenID Connect endpoints and is pinned to one workspace. "Sign in with Microsoft" (`MicrosoftSessionsController` and `MicrosoftSignIn`) uses Entra ID OpenID Connect, validates the ID token (`Microsoft::IdTokenVerifier`), and is pinned to `TEAMS_TENANT_ID`. Both share `PlatformSignIn`, and `User.from_identity(platform, identity)` finds or creates the account:

1. It looks up an existing account by its Slack `UserIdentity`.
2. If there isn't one, it links an existing account by a Slack-verified email.
3. Otherwise it creates a standard account.

Anyone who manages a standup can make other people in it managers, or remove them, from the People tab (`Api::StandupManagersController`). This creates or removes a `StandupOwnership` for that standup only. Someone who has never signed in gets an account tied to their user ID on the standup's platform, and they're matched to it when they first sign in. A standup always keeps at least one manager.

### One API, two ways in

Everything the console shows comes from `/api`, the same API that scripts use. Every request acts as a user, who can arrive one of two ways, and `Api::BaseController` picks exactly one per request:

```mermaid
flowchart TD
    R[Request to /api] --> H{Authorization header?}
    H -->|yes| T{Bearer token matches<br/>an active user's access token?}
    T -->|no| U401[401]
    T -->|yes| TP[That user<br/>no CSRF, no session]
    H -->|no| S[Session cookie]
    S --> C{Changes data?}
    C -->|yes| X{Valid X-CSRF-Token?}
    X -->|no| E422[422]
    X -->|yes| SP[Signed-in user<br/>and member]
    C -->|no| SP
```

A wrong token is always rejected; it never falls back to the cookie. Both ways end up as a `Principal` (`app/models/principal.rb`) for the same user, so authorization doesn't care how someone arrived: admins can manage every standup, and everyone else only the standups they own. Audit log entries record that user, with `auth_method: "access_token"` for token requests. Tokens are looked up by their SHA-256 digest, and a digest shared by two accounts is refused.

Every `/api` action has to check authorization. `Api::BaseController` runs `verify_authorized` after each action, and it raises `AuthorizationNotPerformed` unless the action called one of:

- `authorize_standup!`, for actions on one standup (`set_standup` does this for nested routes)
- `require_admin!`, for admin-only endpoints
- `require_member!`, for the member area (`/api/me/*`), which only reads the signed-in member's own data and needs a session
- `skip_authorization`, for actions any signed-in user may take, such as creating a standup or listing the ones they manage

`test/controllers/api/authorization_check_test.rb` fails if any routed `/api` controller is missing this check.

Avatars use each person's Slack photo when we have one. Teams photos aren't public URLs, so Teams participants show initials. `avatar_url` on `StandupParticipant` and `User` is filled in whenever the app already talks to Slack about that person: user search and resolution, channel sync, timezone refresh, and Slack sign-in, which also refreshes that person's participant rows. `StandupParticipant` and `User` only store `https` URLs (`AvatarUrl`), so serializers can pass them straight through. If a photo is missing or fails to load, the avatar falls back to initials.

Slack and Microsoft guests are refused at sign-in. Since anyone else can sign in, non-admins only see public channels in channel discovery, and can only sync participants from channels they belong to.

Everyone signed in with Slack or Microsoft can use the console for the standups they own, and the member area under `/me` for the standups they're in. Accounts can also sign in with an email and access token. Only a SHA-256 digest of the token is stored.

- **Admins** also get an **Admin** page (`/admin`) that shows database, job queue, and Slack health, usage, users, failed reports, and recent audit log entries.

### The console

The console lives in [`frontend/`](../frontend). It's a Vite + TypeScript + React app built with [Primer React](https://primer.style/product/getting-started/react/) and Octicons, and `vite build` writes it to `public/app`.

```mermaid
sequenceDiagram
    participant B as Browser
    participant R as Rails
    B->>R: GET /manager/standups/42
    R-->>B: public/app/index.html (SpaController)
    B->>R: GET /api/session
    R-->>B: user, member, sidebar, platforms, CSRF token, flash
    B->>R: GET /api/standups/42?include=overview
    R-->>B: JSON
    B->>R: PATCH /api/standups/42/pause + X-CSRF-Token
    R-->>B: { standup, notice }
```

- Each standup has five tabs: Overview, Insights, Responses, People (`/participants`), and Settings. Settings has a side nav, like a GitHub repo's settings, with General (`/edit`), Schedule (`/schedule_exceptions`), and Reports (`/report`). Old `/chat_setup` and `/slack_setup` links redirect to General.
- Console URLs are the same as before (`/manager/standups/:id/participants`, `/me/responses`, `/admin`, and so on). `SpaController` serves the app for any browser navigation that isn't `/api`, `/slack`, `/teams`, `/auth`, or a health check, and React Router takes it from there.
- "Sign in with Slack" and "Sign in with Microsoft" are still server-side redirects under `/auth`. When they finish, they send people to a console URL. Any error shows up as a flash, which `GET /api/session` hands to the app once.
- Serializers in `app/serializers/` shape the JSON. They also compute display values such as schedule summaries, status labels and tones, and per-platform wording (`UiFormat`, `PlatformSerializer`), so the browser doesn't reimplement scheduling rules.
- Charts are small SVG components in `frontend/src/components/charts`, so there's no charting dependency.

When you add a console feature, add or extend an `Api::` endpoint first. Scope records with `principal.manageable_standups` or `set_standup`, and record changes with `audit_change!` so they show up in `AuditLog`. Then build the page in `frontend/src/pages` (see [`frontend/README.md`](../frontend/README.md)).

See [API](api.md) for using the API from scripts with an access token.
