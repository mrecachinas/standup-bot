# Handles a direct message from a participant on any platform: DM commands,
# answers to the current question, and edits to earlier answers.
class StandupConversationHandler
  def initialize(chat)
    @chat = chat
  end

  def handle(message)
    return handle_edit(message) if message.edited?

    text = StandupResponseService.normalize_answer_text(message.text)
    return if message.user_id.blank? || text.blank?

    commands = DirectMessageCommands.new(chat)
    command_info = commands.parse(text)
    if command_info
      commands.process(command_info, message.user_id, message.conversation)
      return
    end

    standup_response = pending_response_for(message.user_id)
    StandupResponseService.record_answer(standup_response, text) if standup_response
  end

  private

  attr_reader :chat

  def platform
    chat.key
  end

  def handle_edit(message)
    user_id = message.user_id
    text = StandupResponseService.normalize_answer_text(message.text)

    pending_response = pending_response_for(user_id)
    if pending_response && pending_response.answers.present?
      update_pending_response(pending_response, text)
      return
    end

    completed_response = current_completed_response_for(user_id)
    update_completed_response(completed_response, text) if completed_response
  end

  def pending_response_for(user_id)
    StandupResponse
      .authorized_for(platform, user_id)
      .where(status: "pending")
      .order("standup_responses.created_at DESC")
      .first
  end

  def update_pending_response(standup_response, text)
    return if text.blank?

    standup_response.answers.last["answer"] = text
    standup_response.answers.last["timestamp"] = Time.current
    standup_response.save!
  end

  def update_completed_response(standup_response, text)
    return if text.blank?

    # Edit events don't say which answer changed, so match by text overlap.
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
        .where(platform_user_id: user_id, standup_id: participant.standup_id, status: "completed")
        .for_standup_date(participant.standup_date_for(Time.current), participant.standup_time_zone)
        .order(created_at: :desc)
        .first
    end.max_by(&:created_at)
  end

  def active_participants_for(user_id)
    StandupParticipant
      .on_platform(platform)
      .where(platform_user_id: user_id, active: true)
      .merge(Standup.active)
      .includes(:standup)
  end
end
