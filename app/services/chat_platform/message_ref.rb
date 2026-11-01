module ChatPlatform
  # Where a sent message landed: the conversation/channel and the platform's
  # message ID (Slack ts, Teams activity ID).
  MessageRef = Struct.new(:channel, :id, keyword_init: true) do
    def self.from_hash(response, id_key:)
      return if response.blank?

      channel = response["channel"] || response[:channel]
      id = response[id_key.to_s] || response[id_key.to_sym]
      return if channel.blank? && id.blank?

      new(channel: channel, id: id)
    end
  end
end
