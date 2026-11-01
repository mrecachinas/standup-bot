class SlackEventProcessorJob < ApplicationJob
  queue_as :default

  def perform(event)
    message = inbound_message(event)
    StandupConversationHandler.new(ChatPlatform.for(:slack)).handle(message) if message
  end

  private

  def inbound_message(event)
    return unless event["type"] == "message"

    if event["subtype"] == "message_changed"
      return ChatPlatform::InboundMessage.new(
        platform: :slack,
        user_id: event.dig("message", "user") || event["user"],
        text: event.dig("message", "text"),
        conversation: event["channel"],
        edited: true
      )
    end

    # Ignore bot messages and other non-plain-text message subtypes.
    return if event["subtype"].present?

    ChatPlatform::InboundMessage.new(
      platform: :slack,
      user_id: event["user"],
      text: event["text"],
      conversation: event["channel"],
      edited: false
    )
  end
end
