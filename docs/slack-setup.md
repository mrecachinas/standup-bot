# Slack setup

To send and receive messages, Standup Bot needs a Slack app installed in your workspace. Slack has to be able to reach your app over HTTPS, so for local testing you'll need a tunnel such as [ngrok](https://ngrok.com/).

## 1. Get a public URL

In production, this is your app's domain. Locally, start Rails and expose it:

```bash
ngrok http 3000
```

Copy the `https://…ngrok-free.app` URL that ngrok gives you.

## 2. Create the Slack app from a manifest

The app can generate a Slack app manifest with all the scopes, events, and slash commands it needs:

```bash
APP_URL=https://your-domain.example bin/rails slack:manifest > slack-manifest.yml
```

Then go to [api.slack.com/apps](https://api.slack.com/apps), choose **Create New App → From an app manifest**, pick your workspace, and paste in `slack-manifest.yml`.

<details>
<summary>What the manifest sets up (if you'd rather configure the app by hand)</summary>

**Bot token scopes** (under **OAuth & Permissions**):

| Scope | Why |
| --- | --- |
| `channels:read` | Look up channels to post summaries to |
| `chat:write` | Send messages as the bot |
| `commands` | Receive slash commands |
| `im:history` | Receive participants' DM replies |
| `im:write` | Start DMs with participants |
| `users:read` | Look up people and their timezones |

**Event subscriptions**: set the request URL to `https://your-domain/slack/events` and subscribe to the `message.im` bot event.

**Interactivity**: set the request URL to `https://your-domain/slack/interactions`.

**Slash commands**:

| Command | Request URL |
| --- | --- |
| `/standup` | `https://your-domain/slack/commands/standup` |
| `/standup-status` | `https://your-domain/slack/commands/standup-status` |

</details>

## 3. Install the app and set credentials

1. Under **Install App**, install the app to your workspace.
2. Copy the **Bot User OAuth Token** (it starts with `xoxb-`).
3. Under **Basic Information**, copy the **Signing Secret**.
4. Set them as environment variables and restart the app:

```bash
SLACK_BOT_TOKEN=xoxb-...
SLACK_SIGNING_SECRET=...
```

The **Slack** page in the web console shows whether these are configured. Each standup also has a **Slack** tab where you can pick its channel, add people by `@username`, and send a test message to the channel.

## 4. Try it out

Send the bot a DM with `help`. If nothing comes back, check the Rails logs to see whether the event arrived (see [Troubleshooting](development.md#troubleshooting)).

## What participants can do

### Slash commands

| Command | What it does |
| --- | --- |
| `/standup` or `/standup start` | Start your standup now |
| `/standup status` | Check the status of your current standup |
| `/standup skip` | Skip your pending standup |
| `/standup report` | Get a standup report |
| `/standup history [days]` | See your recent standups (defaults to the last 7 days) |
| `/standup help` | List the commands |
| `/standup-status` | Shortcut for `/standup status` |

### DM commands

Participants can also type these in their DM with the bot:

| Command | What it does |
| --- | --- |
| `skip` | Skip the current question |
| `cancel` | Cancel the current standup |
| `away [days]` | Mark yourself away (optionally for a number of days) |
| `back` | Come back from being away |
| `report` | Get a standup report |
| `help` | List the commands |
