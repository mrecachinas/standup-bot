module ChatPlatform
  # A direct message from a person, normalized from a platform event.
  # message_id is the platform's ID for the person's message (Slack ts, Teams
  # activity id). It stays the same when the message is edited, so edits can
  # find the answer they belong to. previous_text is the text before an edit,
  # when the platform sends it (Slack does, Teams doesn't), and sent_at is when
  # the original message was sent.
  InboundMessage = Struct.new(:platform, :user_id, :text, :conversation, :edited, :message_id, :previous_text, :sent_at, keyword_init: true) do
    def edited?
      edited == true
    end
  end
end
