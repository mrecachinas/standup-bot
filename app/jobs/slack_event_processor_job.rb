class SlackEventProcessorJob < ApplicationJob
  queue_as :default

  def perform(event)
    if event["type"] == "message" && event["subtype"] == "message_changed"
      return process_edited_message(event)
    end

    return unless event["type"] == "message"

    # Ignore bot messages and other non-plain-text message subtypes.
    return if event["subtype"].present?

    user_id = event["user"]
    text = StandupResponseService.normalize_answer_text(event["text"])
    channel = event["channel"]

    return if user_id.blank? || text.blank?

    slack_commands = SlackCommands.new(slack_client)
    command_info = slack_commands.parse(text)
    if command_info
      slack_commands.process(command_info, user_id, channel)
      return
    end

    standup_response = StandupResponse
      .authorized_for_slack_user(user_id)
      .where(status: "pending")
      .order("standup_responses.created_at DESC")
      .first

    StandupResponseService.record_answer(standup_response, text) if standup_response
  end

  private

  def process_edited_message(event)
    user_id = event.dig("message", "user") || event["user"]
    text = StandupResponseService.normalize_answer_text(event.dig("message", "text"))

    pending_response = StandupResponse
      .authorized_for_slack_user(user_id)
      .where(status: "pending")
      .order("standup_responses.created_at DESC")
      .first

    if pending_response && pending_response.answers.present?
      update_pending_response(pending_response, text)
      return
    end

    completed_response = current_completed_response_for(user_id)
    update_completed_response(completed_response, text) if completed_response
  end

  def update_pending_response(standup_response, text)
    return if text.blank?

    standup_response.answers.last["answer"] = text
    standup_response.answers.last["timestamp"] = Time.current
    standup_response.save!
  end

  def update_completed_response(standup_response, text)
    return if text.blank?

    # Slack edit events don't say which answer changed, so match by text overlap.
    edited = false

    standup_response.answers.each_with_index do |answer, index|
      if text.include?(answer["answer"]) || answer["answer"].include?(text)
        standup_response.answers[index]["answer"] = text
        standup_response.answers[index]["timestamp"] = Time.current
        edited = true
        break
      end
    end

    unless edited
      Rails.logger.warn "Could not match edited message to any answer for standup response #{standup_response.id}, skipping update"
      return
    end

    standup_response.save!
    StandupResponseService.repost_response(standup_response)
  end

  def current_completed_response_for(user_id)
    active_participants_for(user_id).filter_map do |participant|
      StandupResponse
        .where(slack_id: user_id, standup_id: participant.standup_id, status: "completed")
        .for_standup_date(participant.standup_date_for(Time.current), participant.standup_time_zone)
        .order(created_at: :desc)
        .first
    end.max_by(&:created_at)
  end

  def active_participants_for(user_id)
    StandupParticipant
      .joins(:standup)
      .where(slack_id: user_id, active: true)
      .merge(Standup.active)
      .includes(:standup)
  end
end
