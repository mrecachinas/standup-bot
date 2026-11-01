# The admin page: installation health, usage, users, recent changes, and
# failed report deliveries.
class AdminDashboardSerializer
  OVERALL_TONES = { "healthy" => "success", "degraded" => "warning", "unhealthy" => "danger" }.freeze
  CHECK_TONES = { "ok" => "success", "warn" => "warning", "error" => "danger" }.freeze
  CHECK_LABELS = { "ok" => "Operational", "warn" => "Degraded", "error" => "Down" }.freeze
  HEALTH_CARDS = [
    [ :database, "Database", "database" ],
    [ :job_queue, "Job queue", "stack" ],
    [ :slack_api, "Slack", "hash" ],
    [ :teams_api, "Microsoft Teams", "people" ]
  ].freeze
  RESPONSE_TONES = { "completed" => "success", "expired" => "warning", "cancelled" => "danger" }.freeze

  def initialize(health:, metrics:, users:, owned_standup_counts:, audit_logs:, failed_reports:, daily_activity:, activity_days:)
    @health = health
    @metrics = metrics
    @users = users
    @owned_standup_counts = owned_standup_counts
    @audit_logs = audit_logs
    @failed_reports = failed_reports
    @daily_activity = daily_activity
    @activity_days = activity_days
  end

  def as_json(*)
    {
      health: {
        status: @health[:status],
        status_label: @health[:status].to_s.capitalize,
        status_tone: OVERALL_TONES[@health[:status].to_s],
        checked_at: @health[:timestamp]
      },
      health_checks: HEALTH_CARDS.map { |key, label, icon| health_card(key, label, icon) },
      stats: stats,
      activity_days: @activity_days,
      daily_activity: daily_activity,
      daily_activity_has_pending: @daily_activity.any? { |row| row[:pending].positive? },
      response_totals: response_totals,
      users: @users.map { |user| user_json(user) },
      audit_logs: @audit_logs.map { |log| audit_log_json(log) },
      failed_reports: @failed_reports.map { |report| failed_report_json(report) }
    }
  end

  private

  def stats
    standups = @metrics[:standups]
    recent = @metrics[:recent_activity]
    {
      standups_total: standups[:active] + standups[:inactive],
      standups_active: standups[:active],
      standups_paused: standups[:inactive],
      active_people: standups[:active_people],
      active_participants: standups[:active_participants],
      responses_last_24h: recent[:responses_last_24h],
      completed_last_24h: recent[:completed_last_24h],
      users_active: @users.count(&:active?),
      users_admin: @users.count(&:admin?),
      standup_owners: @owned_standup_counts.keys.size
    }
  end

  def health_card(key, label, icon)
    check = @health[:checks][key] || {}
    state = check[:status].to_s.presence || "warn"
    # An unconfigured chat platform isn't a fault, so its label stays neutral.
    unconfigured = key.in?(%i[slack_api teams_api]) && !check[:configured]
    {
      key: key.to_s,
      label: label,
      icon: icon,
      status: state,
      status_label: unconfigured ? "Not configured" : CHECK_LABELS.fetch(state, state),
      status_tone: unconfigured ? nil : CHECK_TONES[state],
      details: health_details(key, check)
    }
  end

  def health_details(key, check)
    case key
    when :database
      [
        detail("Adapter", check[:adapter] || "—"),
        detail("Latency", check[:latency_ms] ? "#{check[:latency_ms]} ms" : check[:message])
      ]
    when :job_queue
      [
        detail("Adapter", check[:adapter]),
        detail("Pending", check[:pending_jobs] || "—"),
        detail("Failed", check[:failed_jobs] || "—", strong: check[:failed_jobs].to_i.positive?),
        (detail("Error", check[:message]) if check[:message].present?)
      ].compact
    when :slack_api
      [
        detail("Bot token", configured_label(check[:bot_token_configured])),
        detail("Signing secret", configured_label(check[:signing_secret_configured])),
        time_detail("Last message", check[:last_successful_message_at])
      ]
    when :teams_api
      [
        detail("App ID", configured_label(check[:app_id_configured])),
        detail("Client secret", configured_label(check[:app_password_configured])),
        detail("Tenant", configured_label(check[:tenant_id_configured])),
        time_detail("Last message", check[:last_successful_message_at])
      ]
    end
  end

  def detail(label, value, strong: false)
    { label: label, value: value&.to_s, time: nil, strong: strong }
  end

  # The client shows `time` relative to now ("3 minutes ago"), or `value` when it's nil.
  def time_detail(label, value)
    time = Time.zone.parse(value.to_s) if value.present?
    { label: label, value: time ? nil : "—", time: time&.iso8601, strong: false }
  end

  def configured_label(configured)
    configured ? "Configured" : "Missing"
  end

  def daily_activity
    @daily_activity.map do |row|
      pending = row[:pending].positive? ? ", #{row[:pending]} pending" : ""
      row.merge(
        date: row[:date].iso8601,
        label: row[:date].strftime("%b %-d"),
        total: row[:completed] + row[:skipped] + row[:pending] + row[:missed],
        title: "#{row[:date].strftime("%b %-d, %Y")}: #{row[:completed]} completed, #{row[:skipped]} skipped, " \
          "#{row[:missed]} missed#{pending} (#{row[:completion_rate].round}%)"
      )
    end
  end

  def response_totals
    counts = @metrics[:responses]
    total = counts.values.sum
    rows = counts.sort_by { |_status, count| -count }.map do |status, count|
      {
        status: status.to_s,
        label: status.to_s.titleize,
        count: count,
        percent: total.positive? ? (count * 100.0 / total).round(1) : 0,
        tone: RESPONSE_TONES[status.to_s]
      }
    end
    { total: total, statuses: rows }
  end

  def user_json(user)
    owned = @owned_standup_counts.fetch(user.id, 0)
    {
      id: user.id,
      name: user.name,
      email: user.email,
      placeholder_email: user.placeholder_email?,
      subtitle: user.placeholder_email? ? identity_labels(user) : user.email,
      identities: user.identities.map { |identity| { platform: identity.platform, platform_user_id: identity.platform_user_id } },
      avatar_url: (user.avatar_url if SlackAvatar.safe_url?(user.avatar_url)),
      admin: user.admin?,
      access_label: user.admin? ? "Admin" : "Member",
      access_tone: user.admin? ? "accent" : nil,
      owned_standups_count: owned,
      owned_standups_label: user.admin? ? "All" : owned.to_s,
      last_signed_in_at: user.last_signed_in_at&.iso8601,
      active: user.active?,
      status_label: user.active? ? "Active" : "Disabled",
      status_tone: user.active? ? "success" : nil
    }
  end

  def identity_labels(user)
    user.identities.map { |identity| "#{ChatPlatform.for(identity.platform).label} #{identity.platform_user_id}" }.join(", ")
  end

  def audit_log_json(log)
    {
      id: log.id,
      action: log.action,
      action_label: log.action.tr("._", "  "),
      actor_name: log.actor&.name || log.actor_label || log.actor_email || "System",
      actor_avatar_url: (log.actor.avatar_url if log.actor && SlackAvatar.safe_url?(log.actor.avatar_url)),
      auditable_type: log.auditable_type,
      auditable_label: "#{log.auditable_type.to_s.titleize} ##{log.auditable_id}",
      auditable_id: log.auditable_id,
      created_at: log.created_at&.iso8601
    }
  end

  def failed_report_json(report)
    {
      id: report.id,
      standup_id: report.standup_id,
      standup_name: report.standup&.name,
      error_message: report.error_message.presence || "Unknown error",
      requested_at: report.requested_at&.iso8601
    }
  end
end
