class SlackEventProcessorJob < ApplicationJob
  queue_as :inbound
  limits_concurrency key: ->(event) { ApplicationJob.inbound_concurrency_key(:slack, event["user"] || event.dig("message", "user")) },
    group: INBOUND_CONCURRENCY_GROUP, duration: INBOUND_CONCURRENCY_DURATION

  def perform(event)
    message = inbound_message(event)
    StandupConversationHandler.new(ChatPlatform.for(:slack)).handle(message) if message
  end

  private

  def inbound_message(event)
    return unless event["type"] == "message"
    return if SlackInbound.bot_event?(event.with_indifferent_access)

    if event["subtype"] == "message_changed"
      return ChatPlatform::InboundMessage.new(
        platform: :slack,
        user_id: event.dig("message", "user") || event["user"],
        text: event.dig("message", "text"),
        conversation: event["channel"],
        edited: true,
        message_id: event.dig("message", "ts"),
        previous_text: event.dig("previous_message", "text"),
        sent_at: slack_time(event.dig("message", "ts"))
      )
    end

    # Ignore bot messages and other non-plain-text message subtypes.
    return if event["subtype"].present?

    ChatPlatform::InboundMessage.new(
      platform: :slack,
      user_id: event["user"],
      text: event["text"],
      conversation: event["channel"],
      edited: false,
      message_id: event["ts"],
      sent_at: slack_time(event["ts"])
    )
  end

  def slack_time(ts)
    ChatPlatform::SlackAdapter.time_from_ts(ts)
  end
end
