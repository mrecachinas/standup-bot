# The /standup command family (start, status, skip, report, history, help) and
# the keywords people can type in their DM with the bot, for any platform.
# Returns ChatPlatform::Reply objects; callers render them.
class StandupCommandHandler
  Reply = ChatPlatform::Reply
  DEFAULT_AWAY_DAYS = 7
  RESTART_ACTION_ID = "standup_restart".freeze
  # The "Not today?" menu on a run's first message.
  KICKOFF_MENU_ACTION_ID = "standup_kickoff_menu".freeze
  KICKOFF_MENU_PLACEHOLDER = "Not today?".freeze
  KICKOFF_CHOICES = {
    "skip" => "Skip today",
    "away_1" => "I'm out today",
    "away_7" => "I'm out for a week"
  }.freeze
  DIRECT_MESSAGE_COMMANDS = {
    "help" => "Show this help message",
    "report" => "Generate a standup report",
    "skip" => "Skip the current question in your standup",
    "cancel" => "Cancel the current standup",
    "away [days]" => "Mark yourself as away (#{DEFAULT_AWAY_DAYS} days unless you say otherwise)",
    "back" => "Return from away status"
  }.freeze

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

  # Returns nil when the text isn't a DM command, so the caller can treat it as an answer.
  # message_id is the platform ID of the DM, so a skipped answer can be filled
  # in later by editing the "skip" message.
  def direct_message(text, message_id: nil)
    case text.to_s.strip
    when /\Ahelp\z/i then direct_message_help
    when /\Areport\z/i then report
    when /\Askip\z/i then skip_question(message_id: message_id)
    when /\Acancel\z/i then cancel
    when /\Aaway(?:\s+(\d+))?\z/i then away(($1 || DEFAULT_AWAY_DAYS).to_i)
    when /\Aback\z/i then back
    end
  end

  def start
    participants = active_participants
    return Reply.text("You are not part of any active standups.") if participants.empty?

    if participants.one?
      start_run(participants.first, "Starting #{fmt.bold(participants.first.standup.name)} now. Check your DMs.")
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

    standups = pending_responses.map(&:standup).uniq
    return restartable_reply("You skipped", standups.first) if standups.one?

    names = standups.map { |standup| fmt.bold(standup.name) }.to_sentence
    Reply.text("You skipped #{names}. You can restart them anytime with #{fmt.code("#{base_command} start")}.")
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
    # Runs are dated in the person's timezone, so an evening run isn't listed under tomorrow's UTC date.
    responses = StandupResponse
      .on_platform(platform)
      .includes(:standup)
      .where(platform_user_id: user_id)
      .where("standup_responses.standup_date > ?", user_today - days.days)
      .order(standup_date: :desc, created_at: :desc)
      .limit(10)

    return Reply.text("No standup responses found in the last #{days} day(s).") if responses.empty?

    lines = responses.map do |response|
      answered = Array(response.answers).count { |answer| answer["answer"].present? && answer["answer"] != StandupResponseService::SKIPPED_ANSWER }
      "• #{response.standup_date.to_fs(:month_day)}: #{response.standup.name} — #{response.status} (#{answered} answer(s))"
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

  def direct_message_help
    lines = DIRECT_MESSAGE_COMMANDS.map { |command, description| "• #{fmt.code(command)} - #{description}" }
    Reply.text("#{fmt.bold("Available Commands:")}\n#{lines.join("\n")}")
  end

  def skip_question(message_id: nil)
    response = StandupResponse.latest_pending_for(platform, user_id)
    return Reply.text("You don't have an active standup to skip questions for.") unless response

    # The next question (or the wrap-up message) is the acknowledgement.
    StandupResponseService.skip_question(response, message_id: message_id)
    Reply.none
  end

  def cancel
    response = StandupResponse.latest_pending_for(platform, user_id)
    return Reply.text("You don't have an active standup to cancel.") unless response

    response.update!(status: "cancelled")
    restartable_reply("You cancelled", response.standup)
  end

  def away(days)
    participants = active_participants.to_a
    return Reply.text("You're not currently part of any active standups.") if participants.empty?

    return_date = mark_away(participants, days)
    Reply.text("You've been marked as away from standups until #{return_date.to_fs(:weekday_month_day)}. Type #{fmt.code("back")} anytime to return early.")
  end

  def back
    # Inactive rows (from `away`) plus rows paused with a current away date (set on the web)
    participant_ids = StandupParticipant
      .in_active_standups(platform, user_id)
      .where("standup_participants.active = ? OR standup_participants.vacation_until >= ?", false, user_today)
      .pluck(:id)
    return Reply.text("You're already active in all your standups.") if participant_ids.empty?

    StandupParticipant.where(id: participant_ids).update_all(active: true, vacation_until: nil)
    Reply.text("Welcome back! You'll now receive standup prompts again.")
  end

  # Someone picked a standup from a selection reply.
  def start_selected(standup_id)
    with_selected_participant(standup_id) do |standup, participant|
      start_run(participant, "Starting #{fmt.bold(standup.name)} now. Check your DMs.")
    end
  end

  # Someone clicked Restart on a skipped or cancelled standup.
  def restart(standup_id)
    with_selected_participant(standup_id) do |standup, participant|
      start_run(participant, "Restarting #{fmt.bold(standup.name)}…")
    end
  end

  # Menu options for a run's first message. Each value names the choice and
  # the run (standup and date), so a menu from an earlier run can't act on a newer one.
  def self.kickoff_menu(standup_id, standup_date)
    options = KICKOFF_CHOICES.map do |choice, text|
      { text: text, value: [ choice, standup_id, standup_date.iso8601 ].join(":") }
    end
    { action_id: KICKOFF_MENU_ACTION_ID, placeholder: KICKOFF_MENU_PLACEHOLDER, options: options }
  end

  # Someone picked from the "Not today?" menu on a run's first message.
  def kickoff_choice(value)
    choice, standup_id, date = value.to_s.split(":", 3)
    standup_date = parse_date(date)
    return Reply.text("That option isn't available anymore.") unless KICKOFF_CHOICES.key?(choice) && standup_date

    with_selected_participant(standup_id) do |standup, _participant|
      response = StandupResponse.find_by(platform_user_id: user_id, standup_id: standup.id, standup_date: standup_date)
      choice == "skip" ? skip_run(standup, response) : out_of_office(choice.delete_prefix("away_").to_i)
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

  def skip_run(standup, response)
    case response&.status
    when "pending"
      StandupResponseService.skip_remaining_questions(response, notify: false)
      restartable_reply("You skipped", standup)
    when "completed"
      Reply.text("You've already finished #{fmt.bold(standup.name)} for today. ✅")
    when "skipped", "cancelled"
      restartable_reply("You skipped", standup)
    else
      Reply.text("#{fmt.bold(standup.name)} isn't waiting on you right now.")
    end
  end

  # Skips the runs waiting on the person today, in any standup, and marks them
  # away until `days` from now, the same as the `away` command.
  def out_of_office(days)
    participants = active_participants.to_a
    return Reply.text("You're not currently part of any active standups.") if participants.empty?

    skipped = participants.flat_map { |participant| pending_responses_for(participant).to_a }
    skipped.each { |response| StandupResponseService.skip_remaining_questions(response, notify: false) }
    return_date = mark_away(participants, days)

    names = skipped.map { |response| fmt.bold(response.standup.name) }.uniq
    text = [
      "Enjoy your time off! 🌴",
      ("I skipped #{names.to_sentence} for today." if names.any?),
      "Your standups resume on #{return_date.to_fs(:weekday_month_day)}. Type #{fmt.code("back")} anytime to return early."
    ].compact.join(" ")
    Reply.text(text)
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue Date::Error
    nil
  end

  def report_queued_reply(standup)
    Reply.text("Generating report for #{standup.name}. It will be posted to #{chat.channel_mention(standup.platform_channel, name: standup.platform_channel_name)} shortly.")
  end

  # Queues a fresh run for today unless one is already underway or done, which
  # StandupMessageJob would leave alone, so the reply doesn't promise a DM that never comes.
  def start_run(participant, queued_text)
    name = fmt.bold(participant.standup.name)

    case today_response_for(participant)&.status
    when "pending"
      Reply.text("#{name} is already in progress. Reply in your DM with the bot to keep going.")
    when "completed"
      Reply.text("You've already finished #{name} for today. ✅")
    else
      StandupMessageJob.perform_later(user_id, participant.standup_id, current_standup_date(participant).iso8601, restart: true)
      Reply.text(queued_text)
    end
  end

  def restartable_reply(verb, standup)
    Reply.action(
      "#{verb} #{fmt.bold(standup.name)}. You can restart it anytime.",
      button: { text: "Restart", value: standup.id },
      action_id: RESTART_ACTION_ID
    )
  end

  def selection(text, participants, action_id)
    options = participants.map { |participant| { text: participant.standup.name, value: participant.standup_id } }
    Reply.selection(text, options, action_id: action_id)
  end

  def active_participants
    @active_participants ||= StandupParticipant
      .in_active_standups(platform, user_id)
      .where(active: true)
      .includes(:standup)
      .order("standups.name ASC")
  end

  def today_response_for(participant)
    StandupResponse
      .where(platform_user_id: user_id, standup_id: participant.standup_id)
      .for_standup_date(current_standup_date(participant))
      .order(created_at: :desc)
      .first
  end

  def pending_responses_for(participant)
    StandupResponse
      .pending
      .where(platform_user_id: user_id, standup_id: participant.standup_id)
      .for_standup_date(current_standup_date(participant))
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

  # The person's own timezone (as their standups see it), so dates in replies
  # and away periods follow their calendar rather than UTC's.
  def user_time_zone
    @user_time_zone ||= begin
      participant = active_participants.first || StandupParticipant.on_platform(platform).find_by(platform_user_id: user_id)
      participant&.standup_time_zone || Time.zone
    end
  end

  def user_today
    Time.current.in_time_zone(user_time_zone).to_date
  end

  # Deactivates these rows until return_date and reactivates them at the start
  # of that day in the person's timezone, before that day's standups go out.
  def mark_away(participants, days)
    return_date = user_today + days.days
    participant_ids = participants.map(&:id)
    StandupParticipant.where(id: participant_ids).update_all(active: false, vacation_until: return_date)
    # Reactivate exactly these rows, not ones the person paused some other way.
    ParticipantReactivationJob
      .set(wait_until: return_date.in_time_zone(user_time_zone))
      .perform_later(user_id, participant_ids, platform.to_s, return_date.iso8601)
    return_date
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
