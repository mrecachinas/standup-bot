# Handles a direct message from a participant on any platform: DM commands
# (see StandupCommandHandler#direct_message), answers to the current question,
# and edits to earlier answers.
class StandupConversationHandler
  # Slack's clock and ours can disagree by a little.
  LEGACY_CLOCK_SKEW = 5.seconds

  def initialize(chat)
    @chat = chat
  end

  NOTHING_PENDING = "There's no standup waiting on you right now, so I didn't save that.".freeze

  # Each message is handled once, even when it's delivered again or picked up
  # from DM history (see ProcessedChatMessage.process_once).
  def handle(message)
    return handle_edit(message) if message.edited?

    text = StandupResponseService.normalize_answer_text(message.text)
    return if message.user_id.blank? || text.blank?

    ProcessedChatMessage.process_once(platform: platform, platform_user_id: message.user_id, message_id: message.message_id) do
      handle_new(message, text)
    end
  end

  private

  attr_reader :chat

  def handle_new(message, text)
    reply = StandupCommandHandler.new(chat: chat, user_id: message.user_id).direct_message(text, message_id: message.message_id)
    return chat.send_reply(message.conversation, reply) if reply

    # A message typed before the bot's latest prompt showed up continues the
    # answer before it; anything else answers the current question.
    standup_response = StandupResponse.continued_by(platform, message.user_id, message.sent_at) ||
      StandupResponse.latest_pending_for(platform, message.user_id)
    unless standup_response
      chat.send_reply(message.conversation, ChatPlatform::Reply.text("#{NOTHING_PENDING} #{start_hint}"))
      return
    end

    StandupResponseService.record_answer(standup_response, text, message_id: message.message_id, sent_at: message.sent_at)
  end

  def start_hint
    "Type #{chat.formatter.code("help")} to see what I can do."
  end

  def platform
    chat.key
  end

  # Finds the answer recorded from the edited message and replaces it. Messages
  # that were never recorded as answers (commands, chatter) are left alone.
  def handle_edit(message)
    return if message.user_id.blank? || message.text.blank?
    return if message.previous_text.present? && message.previous_text == message.text

    standup_response, index = StandupResponse.find_answer_for_message(platform, message.user_id, message.message_id) ||
      legacy_answer_for(message)

    unless standup_response
      Rails.logger.info "Edited message #{message.message_id.inspect} doesn't match a recorded answer, skipping"
      return
    end

    StandupResponseService.edit_answer(standup_response, index, message.text, message_id: message.message_id)
  end

  # Answers recorded before message IDs were stored can only be found by the
  # text they had before the edit. To keep unrelated chatter from overwriting
  # an old answer, a candidate must belong to a run that had started by the
  # time the edited message was sent, be recorded no earlier than that send
  # time, and not be a "(skipped)" filler, since those can come from skipping a
  # whole standup rather than from a message. Exactly one candidate across all
  # runs may match. The match then stores the message ID so later edits of the
  # same message find it directly.
  def legacy_answer_for(message)
    return if message.sent_at.blank?

    previous_answer = StandupResponseService.normalize_answer_text(message.previous_text).strip
    return if previous_answer.blank?

    matches = StandupResponse.editable_for(platform, message.user_id).flat_map do |standup_response|
      next [] if standup_response.created_at > message.sent_at + LEGACY_CLOCK_SKEW

      Array(standup_response.answers).each_index.filter_map do |index|
        [ standup_response, index ] if legacy_match?(standup_response.answers[index], previous_answer, message.sent_at)
      end
    end
    unless matches.one?
      Rails.logger.warn "Edited message matches #{matches.size} answers, skipping" if matches.many?
      return
    end

    # edit_answer stores the message ID, so later edits find it directly.
    matches.first
  end

  def legacy_match?(answer, previous_answer, sent_at)
    return false if answer["message_id"].present? || answer["answer"] == StandupResponseService::SKIPPED_ANSWER
    return false unless answer["answer"].to_s.strip == previous_answer

    recorded_at = answer_time(answer)
    recorded_at.present? && recorded_at >= sent_at - LEGACY_CLOCK_SKEW
  end

  def answer_time(answer)
    Time.zone.parse(answer["timestamp"].to_s)
  rescue ArgumentError
    nil
  end
end
