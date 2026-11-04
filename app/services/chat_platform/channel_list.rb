module ChatPlatform
  # Channels from discovery, plus a note for people when some couldn't be
  # listed (for example, private Slack channels without the groups:read scope).
  class ChannelList < Array
    attr_reader :notice

    def initialize(records = [], notice: nil)
      super(records)
      @notice = notice
    end
  end
end
