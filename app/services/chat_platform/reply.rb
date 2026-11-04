module ChatPlatform
  # A platform-neutral reply to a command: plain text, text plus a list of
  # standups to choose from, text plus a single button, or nothing at all.
  # Each platform renders it in its own format.
  Reply = Struct.new(:text, :options, :action_id, :button, :status, keyword_init: true) do
    def self.text(text, status: :ok)
      new(text: text, status: status)
    end

    def self.selection(text, options, action_id:)
      new(text: text, options: options, action_id: action_id, status: :ok)
    end

    # button: { text:, value: }
    def self.action(text, button:, action_id:)
      new(text: text, button: button, action_id: action_id, status: :ok)
    end

    # For commands whose effect speaks for itself, like skipping to the next question.
    def self.none
      new(status: :ok)
    end

    def selection?
      options.present?
    end

    def action?
      button.present?
    end

    def none?
      text.blank? && !selection? && !action?
    end
  end
end
