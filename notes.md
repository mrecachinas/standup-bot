### Schema/Data Structure

standup_schedule
- name
- schedule (cron syntax?)
- timezone
- channel

junction table for users and standup_schedule
- user_id
- standup_schedule_id

What about a YAML in a team's repo like

```yaml
standup:
  name: Daily Standup
  schedule: "0 9 * * *"
  timezone: "America/New_York" # or "local"?
  channel: prodsec-engineering # Slack channel name
  participants:
    - mrecachinas
    - bkungl
    - boveus
  intro: Good morning! Time for standup. When you're ready, please answer the following # could have a default
  questions:
    - What are your focus areas for today?
    - Do you need any help from anyone in the team?
    - Want to share something funny or interesting with your team? (Optional)
  outro: Thanks! Have a great day! # could have a default
```

Could this be an action?
- Probably not... schedule couldn't send at a user's local time. Maybe Slack supports "scheduling" messages?
- Probably not... we wouldn't be able to listen to each person's response individually with an Action.