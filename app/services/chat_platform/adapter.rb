module ChatPlatform
  # The contract every chat platform implements. Return values are
  # platform-neutral: MessageRef for sent messages, UserProfile for people, and
  # plain hashes with "id" and "label" keys for discovery records.
  class Adapter
    UNKNOWN_USER = "Unknown User".freeze

    def key
      raise NotImplementedError
    end

    def label
      raise NotImplementedError
    end

    def configured?
      raise NotImplementedError
    end

    def formatter
      raise NotImplementedError
    end

    # Messaging

    def send_direct_message(user_id, text)
      raise NotImplementedError
    end

    # Posts plain text to a channel, or to a person when given a user ID.
    def send_message(target, text)
      raise NotImplementedError
    end

    # answers: [{ question:, answer: }] with skipped and blank answers removed.
    def post_standup_update(channel, display_name:, answers:)
      raise NotImplementedError
    end

    def update_standup_update(channel, message_id, display_name:, answers:)
      raise NotImplementedError
    end

    def post_report(channel, text, outro: nil)
      raise NotImplementedError
    end

    # options: [{ text:, value: }]
    def send_selection(target, text, options, action_id:)
      raise NotImplementedError
    end

    # People and channels

    def user_profile(user_id)
      raise NotImplementedError
    end

    def search_users(query: nil, limit: 100)
      raise NotImplementedError
    end

    def list_channels(query: nil, limit: 100)
      raise NotImplementedError
    end

    def channel_member_ids(channel)
      raise NotImplementedError
    end

    # Returns hashes ready for StandupParticipantImporter#sync_profiles.
    def channel_member_profiles(channel)
      raise NotImplementedError
    end

    def connection_status
      raise NotImplementedError
    end

    def valid_user_id?(value)
      raise NotImplementedError
    end

    def normalize_user_id(value)
      raise NotImplementedError
    end

    # Whether typed input is meant as a user ID rather than a name to look up.
    def looks_like_user_id?(value)
      valid_user_id?(value)
    end

    # Completes "must be ..." in validation errors.
    def user_id_hint
      raise NotImplementedError
    end

    def valid_channel?(value)
      raise NotImplementedError
    end

    def normalize_channel(value)
      raise NotImplementedError
    end

    def channel_hint
      raise NotImplementedError
    end

    # Shared helpers

    def display_name_for(user_id)
      user_profile(user_id)&.preferred_name || UNKNOWN_USER
    end

    def channel_reference(channel, name: nil)
      formatter.channel_reference(name.presence || channel)
    end

    def standup_update_heading(display_name)
      formatter.bold("#{display_name}'s Standup Update:")
    end

    def answer_sections(answers)
      answers.map { |answer| "#{formatter.bold(answer[:question])}\n#{answer[:answer]}" }
    end

    def standup_update_text(display_name, answers)
      [ standup_update_heading(display_name), "", answer_sections(answers).join("\n\n") ].join("\n")
    end
  end
end
