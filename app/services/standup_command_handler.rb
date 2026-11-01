# The /standup command family (start, status, skip, report, history, help) for
# any platform. Returns ChatPlatform::Reply objects; callers render them.
class StandupCommandHandler
  Reply = ChatPlatform::Reply

  def initialize(chat:, user_id:, base_command: "/standup", status_command: "/standup-status")
    @chat = chat
    @user_id = user_id.to_s
    @base_command = base_command
    @status_command = status_command
  end

  def run(command_text)
    command_text = command_text.to_s.strip

    case command_text
    when "", /\Astart\z/i
      start
    when /\Astatus\z/i
      status
    when /\Askip\z/i
      skip
    when /\Areport\z/i
      report
    when /\Ahistory(?:\s+(\d+))?\z/i
      history(($1 || 7).to_i)
    when /\Ahelp\z/i
      help
    else
      help("I don't recognize #{fmt.code(command_text)}.")
    end
  end

  def start
    participants = active_participants
    return Reply.text("You are not part of any active standups.") if participants.empty?

    if participants.one?
      participant = participants.first
      standup = participant.standup
      StandupMessageJob.perform_later(user_id, standup.id, current_standup_date(participant).iso8601)
      Reply.text("Starting #{standup.name} now. Check your DMs.")
    else
      selection("Which standup would you like to start?", participants, "standup_start_selection")
    end
  end

  def status
    participants = active_participants
    return Reply.text("You are not part of any active standups.") if participants.empty?

    lines = participants.map do |participant|
      status_line(participant.standup, today_response_for(participant))
    end

    Reply.text("#{fmt.bold("Standup status:")}\n#{lines.join("\n")}")
  end

  def skip
    pending_responses = active_participants.flat_map do |participant|
      pending_responses_for(participant).to_a
    end.uniq

    return Reply.text("You don't have an active standup to skip.") if pending_responses.empty?

    pending_responses.each do |response|
      StandupResponseService.skip_remaining_questions(response, notify: false)
    end

    Reply.text("Skipped remaining questions for #{pending_responses.count} standup(s).")
  end

  def report
    participants = active_participants
    return Reply.text("You are not part of any active standups.") if participants.empty?

    if participants.one?
      participant = participants.first
      StandupCollectionJob.perform_later(*standup_collection_args(participant))
      report_queued_reply(participant.standup)
    else
      selection("Which standup report would you like to generate?", participants, "standup_selection")
    end
  end

  def history(days)
    days = days.clamp(1, 90)
    responses = StandupResponse
      .on_platform(platform)
      .includes(:standup)
      .where(platform_user_id: user_id)
      .where("standup_responses.created_at >= ?", days.days.ago)
      .order("standup_responses.created_at DESC")
      .limit(10)

    return Reply.text("No standup responses found in the last #{days} day(s).") if responses.empty?

    lines = responses.map do |response|
      answered = Array(response.answers).count { |answer| answer["answer"].present? && answer["answer"] != StandupResponseService::SKIPPED_ANSWER }
      "• #{response.created_at.strftime('%b %-d')}: #{response.standup.name} — #{response.status} (#{answered} answer(s))"
    end

    Reply.text("#{fmt.bold("Recent standups (last #{days} day(s)):")}\n#{lines.join("\n")}")
  end

  def help(prefix = nil)
    status_aliases = [ fmt.code("#{base_command} status"), (fmt.code(status_command) if status_command) ].compact

    text = [
      prefix,
      fmt.bold("Available #{fmt.code(base_command)} commands:"),
      "• #{fmt.code(base_command)} or #{fmt.code("#{base_command} start")} — start a standup now",
      "• #{status_aliases.join(' or ')} — check today's progress",
      "• #{fmt.code("#{base_command} skip")} — skip remaining questions for active standups",
      "• #{fmt.code("#{base_command} report")} — generate a standup report",
      "• #{fmt.code("#{base_command} history [days]")} — show recent responses",
      "• #{fmt.code("#{base_command} help")} — show this help"
    ].compact.join("\n")

    Reply.text(text)
  end

  # Someone picked a standup from a selection reply.
  def start_selected(standup_id)
    with_selected_participant(standup_id) do |standup, participant|
      StandupMessageJob.perform_later(user_id, standup.id, participant.standup_date_for(Time.current).iso8601)
      Reply.text("Starting #{standup.name} now. Check your DMs.")
    end
  end

  def report_selected(standup_id)
    with_selected_participant(standup_id) do |standup, participant|
      StandupCollectionJob.perform_later(*standup_collection_args(participant))
      report_queued_reply(standup)
    end
  end

  private

  attr_reader :chat, :user_id, :base_command, :status_command

  def fmt
    chat.formatter
  end

  def platform
    chat.key
  end

  def with_selected_participant(standup_id)
    standup = Standup.find_by(id: standup_id)
    return Reply.text("I couldn't find that standup.") unless standup

    participant = user_id.present? ? standup.standup_participants.find_by(platform_user_id: user_id, active: true) : nil
    return Reply.text("You are not a participant in that standup.") unless participant

    yield standup, participant
  end

  def report_queued_reply(standup)
    Reply.text("Generating report for #{standup.name}. It will be posted to #{chat.channel_reference(standup.platform_channel)} shortly.")
  end

  def selection(text, participants, action_id)
    options = participants.map { |participant| { text: participant.standup.name, value: participant.standup_id } }
    Reply.selection(text, options, action_id: action_id)
  end

  def active_participants
    @active_participants ||= StandupParticipant
      .on_platform(platform)
      .includes(:standup)
      .where(platform_user_id: user_id, active: true)
      .merge(Standup.active)
      .order("standups.name ASC")
  end

  def today_response_for(participant)
    StandupResponse
      .where(platform_user_id: user_id, standup_id: participant.standup_id)
      .for_standup_date(current_standup_date(participant), participant.standup_time_zone)
      .order(created_at: :desc)
      .first
  end

  def pending_responses_for(participant)
    StandupResponse
      .pending
      .where(platform_user_id: user_id, standup_id: participant.standup_id)
      .for_standup_date(current_standup_date(participant), participant.standup_time_zone)
  end

  def standup_collection_args(participant)
    [
      participant.standup_id,
      current_standup_date(participant).iso8601,
      participant.standup_time_zone.tzinfo.name
    ]
  end

  def current_standup_date(participant)
    participant.standup_date_for(Time.current)
  end

  def status_line(standup, response)
    return "• #{standup.name}: not started" unless response

    case response.status
    when "pending"
      answered = response.answers&.size || 0
      "• #{standup.name}: in progress (#{answered}/#{standup.questions.size} questions answered)"
    when "completed"
      "• #{standup.name}: complete ✅"
    else
      "• #{standup.name}: #{response.status}"
    end
  end
end
