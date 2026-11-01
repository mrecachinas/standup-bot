module ChatPlatform
  # A direct message from a person, normalized from a platform event.
  InboundMessage = Struct.new(:platform, :user_id, :text, :conversation, :edited, keyword_init: true) do
    def edited?
      edited == true
    end
  end
end
