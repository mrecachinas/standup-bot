module ChatPlatform
  # Slack mrkdwn.
  module SlackFormatter
    module_function

    def bold(text)
      "*#{text}*"
    end

    def italic(text)
      "_#{text}_"
    end

    def code(text)
      "`#{text}`"
    end

    def channel_reference(channel)
      "##{channel}"
    end
  end
end
