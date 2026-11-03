# Handles a verified Teams activity: answers and edits in the bot's 1:1 chat,
# DM commands (skip, away, ...), "standup ..." commands, and card choices.
class TeamsActivityProcessorJob < ApplicationJob
  queue_as :default

  SUBCOMMAND = /start|status|skip|report|help|history(?:\s+\d+)?/i
  PERSONAL_COMMAND = /\A\/?standup(?:\s+(?<command>#{SUBCOMMAND}))?\s*\z/i
  STATUS_COMMAND = /\A\/?standup-status\s*\z/i
  MENTION_COMMAND = /\A(?:\/?standup\s*)?(?<command>.*)\z/im

  def perform(activity)
    @activity = activity
    remember_conversation

    case activity["type"]
    when "message" then handle_message
    when "messageUpdate" then handle_edit
    end
  end

  private

  attr_reader :activity

  def chat
    ChatPlatform.for(:teams)
  end

  def user_id
    activity.dig("from", "aadObjectId").presence&.downcase
  end

  def conversation_id
    activity.dig("conversation", "id")
  end

  def personal?
    activity.dig("conversation", "conversationType") == "personal"
  end

  def remember_conversation
    return unless personal? && user_id.present? && conversation_id.present?

    chat.remember_conversation(user_id: user_id, conversation_id: conversation_id, service_url: activity["serviceUrl"], tenant_id: activity.dig("conversation", "tenantId"))
  end

  def handle_message
    return if user_id.blank?

    value = activity["value"]
    return handle_card_submit(value) if value.is_a?(Hash) && value["action_id"].present?

    text = chat.plain_text(activity["text"])
    return if text.blank?

    # In a channel or group chat the bot only sees @mentions, so treat them as
    # commands and answer privately.
    return reply(command_handler.run(text.match(MENTION_COMMAND)[:command])) unless personal?

    if (command = personal_command(text))
      return reply(command_handler.run(command))
    end

    StandupConversationHandler.new(chat).handle(inbound_message(text, edited: false))
  end

  def handle_edit
    return unless personal? && user_id.present?

    text = chat.plain_text(activity["text"])
    StandupConversationHandler.new(chat).handle(inbound_message(text, edited: true))
  end

  def handle_card_submit(value)
    response = case value["action_id"]
    when "standup_selection" then command_handler.report_selected(value["standup_id"])
    when "standup_start_selection" then command_handler.start_selected(value["standup_id"])
    when StandupCommandHandler::RESTART_ACTION_ID then command_handler.restart(value["standup_id"])
    else ChatPlatform::Reply.text("That choice isn't supported.")
    end

    reply(response)
  end

  def personal_command(text)
    return "status" if text.match?(STATUS_COMMAND)

    match = text.match(PERSONAL_COMMAND)
    match[:command].to_s if match
  end

  def command_handler
    StandupCommandHandler.new(chat: chat, user_id: user_id, base_command: "standup", status_command: nil)
  end

  def reply(reply)
    chat.send_reply(personal? ? conversation_id : user_id, reply)
  end

  def inbound_message(text, edited:)
    # Teams sends the edited message's original activity id with messageUpdate.
    ChatPlatform::InboundMessage.new(platform: :teams, user_id: user_id, text: text, conversation: conversation_id, edited: edited, message_id: activity["id"])
  end
end
