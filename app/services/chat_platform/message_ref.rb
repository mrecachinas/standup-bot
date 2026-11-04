module ChatPlatform
  # Where a sent message landed: the conversation/channel, the platform's
  # message ID (Slack ts, Teams activity ID), and when the platform says it was
  # sent, when it says (Slack's ts is the send time).
  MessageRef = Struct.new(:channel, :id, :sent_at, keyword_init: true) do
    def self.from_hash(response, id_key:, sent_at: nil)
      return if response.blank?

      channel = response["channel"] || response[:channel]
      id = response[id_key.to_s] || response[id_key.to_sym]
      return if channel.blank? && id.blank?

      new(channel: channel, id: id, sent_at: sent_at&.call(id))
    end
  end
end
