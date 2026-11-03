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
    def post_standup_update(channel, display_name:, standup_name:, answers:)
      raise NotImplementedError
    end

    def update_standup_update(channel, message_id, display_name:, standup_name:, answers:)
      raise NotImplementedError
    end

    def post_report(channel, text, outro: nil)
      raise NotImplementedError
    end

    # options: [{ text:, value: }]
    def send_selection(target, text, options, action_id:)
      raise NotImplementedError
    end

    # Text with one button. button: { text:, value: }
    def send_action(target, text, button:, action_id:)
      raise NotImplementedError
    end

    # The first message of a standup run: a greeting and the first question.
    # Platforms with richer layouts override this; the default is plain text.
    def send_standup_kickoff(user_id, standup_name:, channel:, intro:, question:, question_count:, channel_name: nil, wrapped_up_previous: false)
      parts = standup_kickoff_parts(
        user_id,
        standup_name: standup_name, channel: channel, channel_name: channel_name, intro: intro,
        question: question, question_count: question_count, wrapped_up_previous: wrapped_up_previous
      )
      send_direct_message(user_id, parts.values_at(:wrapped_up, :context, :greeting, :question).compact.join("\n\n"))
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

    def send_reply(target, reply)
      return if reply.none?

      if reply.selection?
        send_selection(target, reply.text, reply.options, action_id: reply.action_id)
      elsif reply.action?
        send_action(target, reply.text, button: reply.button, action_id: reply.action_id)
      else
        send_message(target, reply.text)
      end
    end

    def display_name_for(user_id)
      user_profile(user_id)&.preferred_name || UNKNOWN_USER
    end

    def channel_reference(channel, name: nil)
      formatter.channel_reference(name.presence || channel)
    end

    # A channel reference for message text. Platforms that can link to the
    # channel override this; elsewhere it's the same as #channel_reference.
    def channel_mention(channel, name: nil)
      channel_reference(channel, name: name)
    end

    def first_name_for(user_id)
      user_profile(user_id)&.first_name
    end

    def standup_kickoff_parts(user_id, standup_name:, channel:, intro:, question:, question_count:, channel_name: nil, wrapped_up_previous: false)
      name = formatter.bold(standup_name)
      greeting = [
        "Hi #{first_name_for(user_id).presence || "there"}! 👋 It's time for #{name}",
        (" in #{channel_mention(channel, name: channel_name)}" if channel.present?),
        ".",
        (" #{intro.strip}" if intro.present?)
      ].join

      {
        wrapped_up: ("⏰ Your previous #{name} wasn't finished, so I've wrapped it up." if wrapped_up_previous),
        context: "Starting #{name} · #{question_count} #{"question".pluralize(question_count)} · Reply #{formatter.code("skip")} to pass on one",
        greeting: greeting,
        question: StandupFormatter.format_question(question, formatter: formatter)
      }
    end

    def standup_update_heading(display_name, standup_name)
      "#{formatter.bold(display_name)} posted an update for #{formatter.bold(standup_name)}"
    end

    def answer_sections(answers)
      answers.map { |answer| "#{formatter.bold(answer[:question])}\n#{answer[:answer]}" }
    end

    def standup_update_text(display_name, standup_name, answers)
      [ standup_update_heading(display_name, standup_name), "", answer_sections(answers).join("\n\n") ].join("\n")
    end
  end
end
