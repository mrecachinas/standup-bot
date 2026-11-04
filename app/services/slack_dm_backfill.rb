# Picks up DM replies the bot missed while it couldn't receive Slack events
# (an outage longer than Slack's redeliveries, which stop about 5 minutes on)
# by reading the DM's history, and handles each as if it had just arrived.
# Messages already handled (ProcessedChatMessage) or recorded in any of the
# person's runs are skipped, so running it is always safe.
class SlackDmBackfill
  # Slack's clock and ours can disagree by a little.
  CLOCK_SKEW = 5.seconds

  def initialize(client: SlackClient.instance, chat: ChatPlatform.for(:slack))
    @client = client
    @chat = chat
  end

  # Returns how many missed messages were handled for this pending run.
  def call(standup_response)
    return 0 unless eligible?(standup_response)

    # Replayed into this run, whatever has happened since: during an outage
    # the person saw no new prompts, so later messages continue their answer.
    missed_messages(standup_response).count do |message|
      handler.handle(inbound_message(standup_response, message), target: standup_response.reload)
    end
  end

  private

  attr_reader :client, :chat

  # Only runs started since handled messages were recorded (they note when
  # each prompt went out). In older runs, earlier messages have no record and
  # would be handled again.
  def eligible?(standup_response)
    standup_response.status == "pending" && standup_response.dm_channel.present? &&
      standup_response.prompted_at.present? && standup_response.standup.platform == "slack"
  end

  # The person's plain messages since the run started, oldest first, that
  # haven't been handled. Starting from the run's start rather than its latest
  # answer means a reply missed before a later one was handled is still found.
  def missed_messages(standup_response)
    user_id = standup_response.platform_user_id
    client.dm_history(standup_response.dm_channel, oldest: oldest_ts(standup_response))
      .select { |message| message["user"] == user_id && message["subtype"].blank? && message["bot_id"].blank? && message["text"].present? }
      .sort_by { |message| message["ts"].to_d }
      .reject { |message| ProcessedChatMessage.handled?(platform: :slack, platform_user_id: user_id, message_id: message["ts"]) }
      .reject { |message| StandupResponse.find_answer_for_message(:slack, user_id, message["ts"]) }
  end

  def oldest_ts(standup_response)
    format("%.6f", (standup_response.created_at - CLOCK_SKEW).to_f)
  end

  def inbound_message(standup_response, message)
    ChatPlatform::InboundMessage.new(
      platform: :slack,
      user_id: standup_response.platform_user_id,
      text: message["text"],
      conversation: standup_response.dm_channel,
      edited: false,
      message_id: message["ts"],
      sent_at: ChatPlatform::SlackAdapter.time_from_ts(message["ts"])
    )
  end

  def handler
    @handler ||= StandupConversationHandler.new(chat)
  end
end
