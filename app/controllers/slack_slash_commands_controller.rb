class SlackSlashCommandsController < ApplicationController
  before_action :verify_slack_request

  def standup
    @user_id = params[:user_id].to_s
    command_text = params[:text].to_s.strip

    return render_ephemeral("Missing Slack user id.", status: :bad_request) if @user_id.blank?

    case command_text
    when "", /\Astart\z/i
      trigger_manual_standup
    when /\Astatus\z/i
      render_status
    when /\Askip\z/i
      skip_pending_standups
    when /\Areport\z/i
      generate_report
    when /\Ahistory(?:\s+(\d+))?\z/i
      render_history(($1 || 7).to_i)
    when /\Ahelp\z/i
      render_help
    else
      render_help("I don't recognize `#{command_text}`.")
    end
  end

  def standup_status
    @user_id = params[:user_id].to_s
    return render_ephemeral("Missing Slack user id.", status: :bad_request) if @user_id.blank?

    render_status
  end

  private

  def trigger_manual_standup
    participants = active_participants
    return render_ephemeral("You are not part of any active standups.") if participants.empty?

    if participants.one?
      participant = participants.first
      standup = participant.standup
      StandupMessageJob.perform_later(@user_id, standup.id, current_standup_date(participant).iso8601)
      render_ephemeral("Starting #{standup.name} now. Check your DMs.")
    else
      render_standup_selection(
        "Which standup would you like to start?",
        participants,
        "standup_start_selection"
      )
    end
  end

  def render_status
    participants = active_participants
    return render_ephemeral("You are not part of any active standups.") if participants.empty?

    lines = participants.map do |participant|
      response = today_response_for(participant)
      status_line(participant.standup, response)
    end

    render_ephemeral("*Standup status:*\n#{lines.join("\n")}")
  end

  def skip_pending_standups
    pending_responses = active_participants.flat_map do |participant|
      pending_responses_for(participant).to_a
    end.uniq

    return render_ephemeral("You don't have an active standup to skip.") if pending_responses.empty?

    pending_count = pending_responses.count
    pending_responses.each do |response|
      StandupResponseService.skip_remaining_questions(response, notify: false)
    end

    render_ephemeral("Skipped remaining questions for #{pending_count} standup(s).")
  end

  def generate_report
    participants = active_participants
    return render_ephemeral("You are not part of any active standups.") if participants.empty?

    if participants.one?
      participant = participants.first
      standup = participant.standup
      StandupCollectionJob.perform_later(*standup_collection_args(participant))
      render_ephemeral("Generating report for #{standup.name}. It will be posted to ##{standup.slack_channel} shortly.")
    else
      render_standup_selection(
        "Which standup report would you like to generate?",
        participants,
        "standup_selection"
      )
    end
  end

  def render_history(days)
    days = days.clamp(1, 90)
    responses = StandupResponse
      .includes(:standup)
      .where(slack_id: @user_id)
      .where("created_at >= ?", days.days.ago)
      .order(created_at: :desc)
      .limit(10)

    if responses.empty?
      render_ephemeral("No standup responses found in the last #{days} day(s).")
      return
    end

    lines = responses.map do |response|
      answered = Array(response.answers).count { |answer| answer["answer"].present? && answer["answer"] != "(skipped)" }
      "• #{response.created_at.strftime('%b %-d')}: #{response.standup.name} — #{response.status} (#{answered} answer(s))"
    end

    render_ephemeral("*Recent standups (last #{days} day(s)):*\n#{lines.join("\n")}")
  end

  def render_help(prefix = nil)
    text = [
      prefix,
      "*Available `/standup` commands:*",
      "• `/standup` or `/standup start` — start a standup now",
      "• `/standup status` or `/standup-status` — check today's progress",
      "• `/standup skip` — skip remaining questions for active standups",
      "• `/standup report` — generate a standup report",
      "• `/standup history [days]` — show recent responses",
      "• `/standup help` — show this help"
    ].compact.join("\n")

    render_ephemeral(text)
  end

  def active_participants
    @active_participants ||= StandupParticipant
      .joins(:standup)
      .includes(:standup)
      .where(slack_id: @user_id, active: true)
      .merge(Standup.active)
      .order("standups.name ASC")
  end

  def today_response_for(participant)
    StandupResponse
      .where(slack_id: @user_id, standup_id: participant.standup_id)
      .for_standup_date(current_standup_date(participant), current_standup_zone(participant))
      .order(created_at: :desc)
      .first
  end

  def pending_responses_for(participant)
    StandupResponse
      .pending
      .where(slack_id: @user_id, standup_id: participant.standup_id)
      .for_standup_date(current_standup_date(participant), current_standup_zone(participant))
  end

  def standup_collection_args(participant)
    [
      participant.standup_id,
      current_standup_date(participant).iso8601,
      current_standup_zone(participant).tzinfo.name
    ]
  end

  def current_standup_date(participant)
    participant.standup_date_for(Time.current)
  end

  def current_standup_zone(participant)
    participant.standup_time_zone
  end

  def status_line(standup, response)
    return "• #{standup.name}: not started" unless response

    case response.status
    when "pending"
      answered = response.answers&.size || 0
      "• #{standup.name}: in progress (#{answered}/#{standup.questions.size} questions answered)"
    when "completed"
      "• #{standup.name}: complete ✅"
    when "skipped", "cancelled"
      "• #{standup.name}: #{response.status}"
    else
      "• #{standup.name}: #{response.status}"
    end
  end

  def render_standup_selection(text, participants, action_id)
    render json: {
      response_type: "ephemeral",
      text: text,
      blocks: standup_selection_blocks(text, participants, action_id)
    }
  end

  def standup_selection_blocks(text, participants, action_id)
    [
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: text
        }
      },
      {
        type: "actions",
        elements: [
          {
            type: "static_select",
            placeholder: {
              type: "plain_text",
              text: "Select a standup"
            },
            action_id: action_id,
            options: participants.map do |participant|
              {
                text: {
                  type: "plain_text",
                  text: participant.standup.name
                },
                value: participant.standup_id.to_s
              }
            end
          }
        ]
      }
    ]
  end

  def render_ephemeral(text, status: :ok)
    render json: {
      response_type: "ephemeral",
      text: text
    }, status: status
  end
end
