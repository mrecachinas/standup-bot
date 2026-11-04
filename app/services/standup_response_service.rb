class StandupResponseService
  SKIPPED_ANSWER = "(skipped)".freeze

  def self.chat_for(standup_response)
    ChatPlatform.for_standup(standup_response.standup)
  end

  # Records a message from the person in this run, then sends the next
  # question or, after the last one, posts the update. The answer is saved
  # under a row lock, and the sends happen only once that (and the caller's
  # transaction, such as ProcessedChatMessage.process_once) has committed, in
  # jobs that retry on their own. So concurrent replies can't overwrite each
  # other, a failed send can't undo a saved answer, and nothing is sent for
  # an answer that's rolled back.
  #
  # message_id is the platform's ID for the message: it's kept on the answer so
  # an edit can find it, and a message that's already recorded (a redelivered
  # event) is ignored. sent_at is when the person sent it: a message sent
  # before the bot's latest prompt reached them continues the answer they were
  # giving (see .continuation?), except "skip", which is about the question
  # coming next. Returns whether anything was recorded.
  def self.record_answer(standup_response, text, message_id: nil, sent_at: nil)
    answer_text = normalize_answer_text(text)
    answer_text = SKIPPED_ANSWER if skip_text?(answer_text)

    outcome = standup_response.with_lock do
      if standup_response.answer_index_for_message(message_id)
        :duplicate
      elsif answer_text != SKIPPED_ANSWER && continuation?(standup_response, sent_at)
        continue_answer(standup_response, answer_text, message_id: message_id, sent_at: sent_at) ? :continued : :duplicate
      elsif standup_response.status != "pending"
        :closed
      else
        append_answer(standup_response, answer_text, message_id: message_id, sent_at: sent_at)
        standup_response.status = "completed" if standup_response.answers.size >= standup_response.standup.questions.size
        standup_response.save!
        :answered
      end
    end

    after_commit do
      case outcome
      when :answered
        if standup_response.status == "completed"
          complete_standup_response(standup_response)
        else
          StandupPromptJob.perform_now(standup_response, standup_response.answers.size)
        end
      when :continued
        StandupUpdateJob.perform_now(standup_response) if standup_response.status == "completed"
      end
    end
    %i[answered continued].include?(outcome)
  end

  # Runs the block once the current transaction commits, or right away
  # outside one.
  def self.after_commit(&block)
    ActiveRecord.after_all_transactions_commit(&block)
  end

  def self.skip_question(standup_response, message_id: nil, sent_at: nil)
    record_answer(standup_response, SKIPPED_ANSWER, message_id: message_id, sent_at: sent_at)
  end

  # Whether a message sent at sent_at was typed before the bot's latest prompt
  # in this run reached the person, say "foo" and then "bar" before the next
  # question showed up, or while a finished run's sign-off hasn't gone out.
  # Such a message belongs with an earlier answer.
  def self.continuation?(standup_response, sent_at)
    return false if sent_at.blank? || standup_response.answers.blank?
    return true if awaiting_sign_off?(standup_response)

    standup_response.prompted_at.present? && sent_at < standup_response.prompted_at &&
      %w[pending completed].include?(standup_response.status)
  end

  # A finished run (started since prompts were recorded) whose sign-off
  # hasn't been delivered yet, say while the channel post is being retried.
  def self.awaiting_sign_off?(standup_response)
    standup_response.status == "completed" && standup_response.signed_off_at.nil? && standup_response.prompted_at.present?
  end

  # Adds the message to the answer to the question that was showing when it
  # was sent (each answer notes when its question was asked), in send order.
  # Each message is kept as a part, so editing one later changes just its
  # text. A "skip" adds nothing, and real text replaces a "skip". Returns
  # whether it changed.
  def self.continue_answer(standup_response, answer_text, message_id:, sent_at:)
    return false if answer_text == SKIPPED_ANSWER || answer_text.blank?

    answers = standup_response.answers
    index = answers.rindex { |candidate| (asked_at = parse_time(candidate["asked_at"])) && asked_at <= sent_at } || answers.size - 1
    answer = answers[index]
    parts = answer_parts(answer)
    parts << { "message_id" => message_id.presence&.to_s, "text" => answer_text, "sent_at" => sent_at&.iso8601(6) }.compact
    answer["parts"] = parts.sort_by.with_index { |part, position| [ parse_time(part["sent_at"]) || Time.zone.at(0), position ] }
    answer["answer"] = joined_answer(answer["parts"])
    standup_response.save!
    true
  end

  # An answer's messages: its parts, or the single message it was recorded from.
  def self.answer_parts(answer)
    return answer["parts"].map(&:dup) if answer["parts"].present?

    [ { "message_id" => answer["message_id"], "text" => answer["answer"], "sent_at" => answer["sent_at"] || answer["timestamp"]&.to_s }.compact ]
  end

  def self.joined_answer(parts)
    texts = parts.map { |part| part["text"] }.reject { |text| text.blank? || text == SKIPPED_ANSWER }
    texts.empty? ? SKIPPED_ANSWER : normalize_answer_text(texts.join("\n"))
  end

  def self.parse_time(value)
    value.respond_to?(:in_time_zone) ? value.in_time_zone : Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  # Replaces one recorded answer after the participant edits their message.
  # Editing to "skip" marks the answer skipped. A finished run's channel post
  # is updated (or posted, if every answer was skipped before); unfinished,
  # skipped, or cancelled runs just keep the new text. Edits after the run is
  # finished keep the original answer time and record edited_at, which marks
  # the channel post "(edited)" and shows in the console. message_id, when
  # given, is stored on the answer so later edits find it directly; for an
  # answer made of several messages, it picks the part to change.
  def self.edit_answer(standup_response, index, text, message_id: nil)
    answer_text = normalize_answer_text(text)
    answer_text = SKIPPED_ANSWER if skip_text?(answer_text)

    changed = standup_response.with_lock do
      answer = standup_response.answers[index]
      answer["message_id"] ||= message_id.to_s if answer && answer["parts"].blank? && message_id.present?
      new_text = answer && edited_answer_text(answer, answer_text, message_id)

      if answer.nil? || answer_text.blank? || answer["answer"] == new_text
        standup_response.save! if standup_response.changed?
        false
      else
        answer["answer"] = new_text
        if standup_response.status == "completed"
          answer["edited_at"] = Time.current
        else
          answer["timestamp"] = Time.current
        end
        standup_response.save!
        true
      end
    end

    # The job renders the saved answers, so a retry after a failed update
    # still shows the edit.
    after_commit { StandupUpdateJob.perform_now(standup_response) } if changed && standup_response.status == "completed"
    changed
  end

  # The answer's text after one of its messages is edited. Changes that
  # message's part in place when the answer has several.
  def self.edited_answer_text(answer, answer_text, message_id)
    part = Array(answer["parts"]).find { |candidate| message_id.present? && candidate["message_id"].to_s == message_id.to_s }
    unless part
      # The whole answer is being replaced, so its old messages no longer apply.
      answer.delete("parts")
      return answer_text
    end

    part["text"] = answer_text
    joined_answer(answer["parts"])
  end

  def self.skip_text?(text)
    text.to_s.strip.casecmp?("skip")
  end

  # Locked like record_answer, since slash commands run alongside answer jobs.
  # A run that finished meanwhile is left alone. Returns whether it skipped.
  def self.skip_remaining_questions(standup_response, notify: true)
    standup = standup_response.standup
    skipped = standup_response.with_lock do
      next false unless standup_response.status == "pending"

      standup_response.answers ||= []
      append_answer(standup_response, SKIPPED_ANSWER) while standup_response.answers.size < standup.questions.size
      standup_response.status = "skipped"
      standup_response.save!
      true
    end
    return false unless skipped

    if notify
      chat_for(standup_response).send_direct_message(
        standup_response.platform_user_id,
        "Your remaining #{standup.name} standup questions have been skipped."
      )
    end
    true
  end

  def self.cancel_previous_pending_responses(platform_user_id, standup_id, standup_date = Time.zone.today)
    standup_date = StandupResponse.normalize_date(standup_date)

    previous_pending = StandupResponse
      .where(platform_user_id: platform_user_id, standup_id: standup_id, status: "pending")
      .where(standup_date: ...standup_date)

    # Returns how many were wrapped up, so the next prompt can say so.
    previous_pending.each { |response| response.update!(status: "skipped") }.size
  end

  def self.normalize_answer_text(text)
    normalized_text = text.to_s
    return normalized_text if normalized_text.length <= StandupResponse::MAX_ANSWER_LENGTH

    Rails.logger.warn "Answer exceeds maximum length; truncating to #{StandupResponse::MAX_ANSWER_LENGTH} characters"
    normalized_text.truncate(StandupResponse::MAX_ANSWER_LENGTH, omission: "")
  end

  # sent_at, when known, is the platform's send time for the message, kept so
  # messages that continue the answer can be put in order. asked_at is when
  # the question reached the person, so a late continuation finds its answer.
  def self.append_answer(standup_response, answer_text, message_id: nil, sent_at: nil)
    standup_response.answers ||= []
    standup_response.answers << {
      question: standup_response.standup.questions[standup_response.answers.size],
      answer: answer_text,
      timestamp: Time.current,
      message_id: message_id.presence&.to_s,
      sent_at: sent_at&.iso8601(6),
      asked_at: standup_response.prompted_at&.iso8601(6)
    }.compact
  end

  # Posts the run's update to the standup's channel, or updates the post
  # that's already there, from the answers as saved. With nothing left to
  # show, an existing post is updated to say the person skipped, so answers
  # they've since retracted don't stay up; with no post yet, nothing is
  # posted. Returns :posted, :updated, or :nothing.
  def self.repost_response(standup_response)
    standup = standup_response.standup
    chat = chat_for(standup_response)
    answers = postable_answers(standup_response)
    update = {
      display_name: display_name_for(standup_response),
      standup_name: standup.name,
      answers: answers,
      edited: edited?(standup_response)
    }

    if standup_response.platform_message_id.present?
      chat.update_standup_update(standup.platform_channel, standup_response.platform_message_id, **update)
      return :updated
    end
    return :nothing if answers.empty?

    message = chat.post_standup_update(standup.platform_channel, **update)
    # Keep the message ID so later edits can update the channel post in place.
    standup_response.update!(platform_message_id: message.id) if message&.id.present?
    :posted
  end

  # The last answer is saved; post the update and let the person know.
  def self.complete_standup_response(standup_response)
    StandupMetrics.track(
      "standup.completed",
      standup_id: standup_response.standup_id,
      platform_user_id: standup_response.platform_user_id,
      response_id: standup_response.id,
      duration_seconds: response_duration_seconds(standup_response)
    )
    StandupUpdateJob.perform_now(standup_response, announce: true)
  end

  def self.response_duration_seconds(standup_response)
    return unless standup_response.created_at

    (Time.current - standup_response.created_at).round
  end

  def self.send_next_question(standup_response)
    question = standup_response.standup.questions[standup_response.answers.size]
    chat = chat_for(standup_response)

    message = chat.send_direct_message(
      standup_response.platform_user_id,
      StandupFormatter.format_question(question, formatter: chat.formatter)
    )
    prompted!(standup_response, message)
  end

  # Notes when the bot's latest prompt in this run reached the person: the
  # platform's send time when it reports one, or now. signed_off: it was the
  # sign-off after the run finished.
  def self.prompted!(standup_response, message, signed_off: false)
    sent_at = message.try(:sent_at) || Time.current
    standup_response.update!(prompted_at: sent_at, **({ signed_off_at: sent_at } if signed_off).to_h)
  end

  # The name stored for the participant, so posting doesn't need a profile
  # lookup (those are rate-limited). Looks the person up only if there's none.
  def self.display_name_for(standup_response)
    participant = standup_response.standup.standup_participants.find_by(platform_user_id: standup_response.platform_user_id)
    name = participant&.display_name
    return name if name.present? && name != standup_response.platform_user_id

    chat_for(standup_response).display_name_for(standup_response.platform_user_id)
  end

  # Answers worth posting, as [{ question:, answer: }]. Answers appended in
  # this request still have symbol keys, so read both kinds.
  def self.postable_answers(standup_response)
    Array(standup_response.answers).filter_map do |answer|
      text = answer["answer"] || answer[:answer]
      next if text.blank? || text == SKIPPED_ANSWER

      { question: answer["question"] || answer[:question], answer: text }
    end
  end

  # Whether any answer changed after the run was finished, including answers
  # since edited to "skip" that no longer show. Marks the post "(edited)".
  def self.edited?(standup_response)
    Array(standup_response.answers).any? { |answer| (answer["edited_at"] || answer[:edited_at]).present? }
  end
end
