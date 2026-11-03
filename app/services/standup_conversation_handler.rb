# Handles a direct message from a participant on any platform: DM commands
# (see StandupCommandHandler#direct_message), answers to the current question,
# and edits to earlier answers.
class StandupConversationHandler
  def initialize(chat)
    @chat = chat
  end

  def handle(message)
    return handle_edit(message) if message.edited?

    text = StandupResponseService.normalize_answer_text(message.text)
    return if message.user_id.blank? || text.blank?

    reply = StandupCommandHandler.new(chat: chat, user_id: message.user_id).direct_message(text, message_id: message.message_id)
    return chat.send_reply(message.conversation, reply) if reply

    standup_response = StandupResponse.latest_pending_for(platform, message.user_id)
    StandupResponseService.record_answer(standup_response, text, message_id: message.message_id) if standup_response
  end

  private

  attr_reader :chat

  def platform
    chat.key
  end

  # Finds the answer recorded from the edited message and replaces it. Messages
  # that were never recorded as answers (commands, chatter) are left alone.
  def handle_edit(message)
    return if message.user_id.blank? || message.text.blank?
    return if message.previous_text.present? && message.previous_text == message.text

    standup_response, index = StandupResponse.find_answer_for_message(platform, message.user_id, message.message_id) ||
      legacy_answer_for_text(message.user_id, message.previous_text)

    unless standup_response
      Rails.logger.info "Edited message #{message.message_id.inspect} doesn't match a recorded answer, skipping"
      return
    end

    StandupResponseService.edit_answer(standup_response, index, message.text)
  end

  # Answers recorded before message IDs were stored can only be found by the
  # text they had before the edit. Only an unambiguous match counts.
  def legacy_answer_for_text(user_id, previous_text)
    previous_answer = StandupResponseService.normalize_answer_text(previous_text).strip
    return if previous_answer.blank?

    previous_answer = StandupResponseService::SKIPPED_ANSWER if StandupResponseService.skip_text?(previous_answer)

    StandupResponse.editable_for(platform, user_id).each do |standup_response|
      indexes = Array(standup_response.answers).each_index.select do |index|
        answer = standup_response.answers[index]
        answer["message_id"].blank? && answer["answer"].to_s.strip == previous_answer
      end
      next if indexes.empty?
      return [ standup_response, indexes.first ] if indexes.one?

      Rails.logger.warn "Edited message matches #{indexes.size} answers in standup response #{standup_response.id}, skipping"
      return
    end

    nil
  end
end
