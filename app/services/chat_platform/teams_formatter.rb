module ChatPlatform
  # Teams markdown.
  module TeamsFormatter
    module_function

    def bold(text)
      "**#{text}**"
    end

    def italic(text)
      "_#{text}_"
    end

    def code(text)
      "`#{text}`"
    end

    def channel_reference(channel)
      channel.to_s.include?("|") ? "your team's channel" : channel.to_s
    end
  end
end
