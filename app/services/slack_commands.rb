class SlackCommands
  COMMANDS = {
    report: {
      pattern: /^report$/i,
      description: "Generate a standup report"
    },
    help: {
      pattern: /^help$/i,
      description: "Show this help message"
    },
    skip: {
      pattern: /^skip$/i,
      description: "Skip the current question in your standup"
    },
    cancel: {
      pattern: /^cancel$/i,
      description: "Cancel the current standup"
    },
    away: {
      pattern: /^away(?: (\d+))?$/i,
      description: "Mark yourself as away (optional: specify number of days)"
    },
    back: {
      pattern: /^back$/i,
      description: "Return from away status"
    }
  }

  def initialize(slack_client)
    @slack_client = slack_client
  end

  def parse(text)
    normalized_text = text.to_s.strip
    return nil if normalized_text.blank?

    COMMANDS.each do |command, config|
      match = normalized_text.match(config[:pattern])
      return { command: command, match: match } if match
    end

    nil
  end

  def process(command_info, slack_id, channel)
    command = command_info[:command]
    match = command_info[:match]

    Rails.logger.info "Processing command: #{command} from user: #{slack_id} in channel: #{channel}"

    case command
    when :report
      generate_report(slack_id, channel)
    when :help
      send_help_message(channel)
    when :skip
      skip_current_question(slack_id, channel)
    when :cancel
      cancel_standup(slack_id, channel)
    when :away
      days = match[1]&.to_i || 7
      set_user_away(slack_id, days, channel)
    when :back
      set_user_active(slack_id, channel)
    else
      Rails.logger.warn "Unknown command: #{command}"
      @slack_client.send_message(channel, "Sorry, I don't know how to handle that command.")
    end
  end

  private

  def generate_report(slack_id, channel)
    participants = StandupParticipant
      .joins(:standup)
      .merge(Standup.active)
      .where(slack_id: slack_id, active: true)
      .distinct

    if participants.empty?
      return @slack_client.send_message(channel, "You're not part of any standups.")
    end

    if participants.count == 1
      participant = participants.first
      standup = participant.standup
      StandupCollectionJob.perform_later(
        standup.id,
        participant.standup_date_for(Time.current).iso8601,
        participant.standup_time_zone.tzinfo.name
      )
      @slack_client.send_message(channel, "Generating report for #{standup.name}. It will be posted to ##{standup.slack_channel} shortly.")
    else
      options = participants.map { |p| { text: p.standup.name, value: p.standup.id } }
      @slack_client.send_standup_selection(channel, "Which standup report would you like to generate?", options)
    end
  end

  def send_help_message(channel)
    command_descriptions = COMMANDS.map do |cmd, config|
      "• `#{cmd}` - #{config[:description]}"
    end.join("\n")

    help_text = "*Available Commands:*\n#{command_descriptions}"
    @slack_client.send_message(channel, help_text)
  end

  def skip_current_question(slack_id, channel)
    standup_response = pending_response_for(slack_id)

    if standup_response
      StandupResponseService.skip_question(standup_response)
      @slack_client.send_message(channel, "Question skipped. Moving on to the next one.")
    else
      @slack_client.send_message(channel, "You don't have an active standup to skip questions for.")
    end
  end

  def cancel_standup(slack_id, channel)
    standup_response = pending_response_for(slack_id)

    if standup_response
      standup_response.update!(status: "cancelled")
      @slack_client.send_message(channel, "Your standup has been cancelled.")
    else
      @slack_client.send_message(channel, "You don't have an active standup to cancel.")
    end
  end

  def set_user_away(slack_id, days, channel)
    participants = StandupParticipant
      .joins(:standup)
      .merge(Standup.active)
      .where(slack_id: slack_id, active: true)
      .distinct

    if participants.any?
      # Track which participants we're deactivating so reactivation is precise
      participant_ids = participants.pluck(:id)

      return_date = Date.today + days.days
      count = StandupParticipant.where(id: participant_ids).update_all(active: false, vacation_until: return_date)
      Rails.logger.info "Set #{count} standup participants to inactive for user #{slack_id}"
      SlackUserReactivationJob.set(wait_until: return_date.noon).perform_later(slack_id, participant_ids)

      @slack_client.send_message(
        channel,
        "You've been marked as away from standups until #{return_date.strftime('%A, %B %d')}. Type `back` anytime to return early."
      )
    else
      @slack_client.send_message(channel, "You're not currently part of any active standups.")
    end
  end

  def set_user_active(slack_id, channel)
    # Inactive rows (from `away`) plus rows paused with a current away date (set on the web)
    participants = StandupParticipant
      .joins(:standup)
      .merge(Standup.active)
      .where(slack_id: slack_id)
      .where("standup_participants.active = ? OR standup_participants.vacation_until >= ?", false, Date.current)
      .distinct

    if participants.any?
      participant_ids = participants.pluck(:id)
      count = StandupParticipant.where(id: participant_ids).update_all(active: true, vacation_until: nil)
      Rails.logger.info "Reactivated #{count} standup participants for user #{slack_id}"
      @slack_client.send_message(channel, "Welcome back! You'll now receive standup prompts again.")
    else
      @slack_client.send_message(channel, "You're already active in all your standups.")
    end
  end

  def pending_response_for(slack_id)
    StandupResponse
      .authorized_for_slack_user(slack_id)
      .where(status: "pending")
      .order("standup_responses.created_at DESC")
      .first
  end
end
