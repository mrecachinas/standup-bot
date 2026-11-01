module ChatPlatform
  # A platform-neutral reply to a command: plain text, or text plus a list of
  # standups to choose from. Each platform renders it in its own format.
  Reply = Struct.new(:text, :options, :action_id, :status, keyword_init: true) do
    def self.text(text, status: :ok)
      new(text: text, status: status)
    end

    def self.selection(text, options, action_id:)
      new(text: text, options: options, action_id: action_id, status: :ok)
    end

    def selection?
      options.present?
    end
  end
end
