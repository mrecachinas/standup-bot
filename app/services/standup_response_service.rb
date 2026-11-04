class StandupResponseService
  SKIPPED_ANSWER = "(skipped)".freeze

  def self.chat_for(standup_response)
    ChatPlatform.for_standup(standup_response.standup)
  end

  # message_id is the platform ID of the participant's message, kept on the
  # answer so a later edit of that message can find it.
  def self.record_answer(standup_response, text, message_id: nil)
    answer_text = normalize_answer_text(text)
    return skip_question(standup_response, message_id: message_id) if skip_text?(answer_text)

    append_answer(standup_response, answer_text, message_id: message_id)
    process_answer_update(standup_response)
  end

  def self.skip_question(standup_response, message_id: nil)
    append_answer(standup_response, SKIPPED_ANSWER, message_id: message_id)
    process_answer_update(standup_response)
  end

  # Replaces one recorded answer after the participant edits their message.
  # Editing to "skip" marks the answer skipped. A finished run's channel post
  # is updated (or posted, if every answer was skipped before); unfinished,
  # skipped, or cancelled runs just keep the new text. Edits after the run is
  # finished keep the original answer time and record edited_at, which marks
  # the channel post "(edited)" and shows in the console.
  def self.edit_answer(standup_response, index, text)
    answer_text = normalize_answer_text(text)
    answer_text = SKIPPED_ANSWER if skip_text?(answer_text)
    answer = standup_response.answers[index]
    return false if answer_text.blank? || answer["answer"] == answer_text

    answer["answer"] = answer_text
    if standup_response.status == "completed"
      answer["edited_at"] = Time.current
    else
      answer["timestamp"] = Time.current
    end

    # Update the channel post before saving. If the update fails (e.g. a rate
    # limit the job retries), the old answer is still stored, so the retried
    # edit isn't skipped as unchanged and the post still gets updated.
    repost_response(standup_response) if standup_response.status == "completed"
    standup_response.save!
    true
  end

  def self.skip_text?(text)
    text.to_s.strip.casecmp?("skip")
  end

  def self.skip_remaining_questions(standup_response, notify: true)
    standup = standup_response.standup
    standup_response.answers ||= []

    while standup_response.answers.size < standup.questions.size
      append_answer(standup_response, SKIPPED_ANSWER)
    end

    standup_response.status = "skipped"
    standup_response.save!

    if notify
      chat_for(standup_response).send_direct_message(
        standup_response.platform_user_id,
        "Your remaining #{standup.name} standup questions have been skipped."
      )
    end
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

  def self.append_answer(standup_response, answer_text, message_id: nil)
    standup_response.answers ||= []
    standup_response.answers << {
      question: standup_response.standup.questions[standup_response.answers.size],
      answer: answer_text,
      timestamp: Time.current,
      message_id: message_id.presence
    }.compact
  end

  def self.process_answer_update(standup_response)
    if standup_response.answers.size >= standup_response.standup.questions.size
      complete_standup_response(standup_response)
    else
      send_next_question(standup_response)
    end

    standup_response.save!
  end

  def self.repost_response(standup_response)
    message_id = standup_response.platform_message_id
    return post_individual_response(standup_response) if message_id.blank?

    chat = chat_for(standup_response)
    display_name = chat.display_name_for(standup_response.platform_user_id)
    # With nothing left to show, the post is updated to say the person skipped,
    # so answers they've since retracted don't stay in the channel.
    answers = postable_answers(standup_response)

    chat.update_standup_update(
      standup_response.standup.platform_channel,
      message_id,
      display_name: display_name,
      standup_name: standup_response.standup.name,
      answers: answers,
      edited: edited?(standup_response)
    )
  end

  def self.complete_standup_response(standup_response)
    standup = standup_response.standup
    standup_response.status = "completed"

    chat = chat_for(standup_response)
    channel = chat.channel_mention(standup.platform_channel, name: standup.platform_channel_name)
    completion_message = [
      standup.outro.presence || "Thanks! 🙌",
      "Your update has been posted to #{channel}."
    ].join("\n\n")
    chat.send_direct_message(standup_response.platform_user_id, completion_message)

    post_individual_response(standup_response)

    StandupMetrics.track(
      "standup.completed",
      standup_id: standup.id,
      platform_user_id: standup_response.platform_user_id,
      response_id: standup_response.id,
      duration_seconds: response_duration_seconds(standup_response)
    )
  end

  def self.response_duration_seconds(standup_response)
    return unless standup_response.created_at

    (Time.current - standup_response.created_at).round
  end

  def self.send_next_question(standup_response)
    question = standup_response.standup.questions[standup_response.answers.size]
    chat = chat_for(standup_response)

    chat.send_direct_message(
      standup_response.platform_user_id,
      StandupFormatter.format_question(question, formatter: chat.formatter)
    )
  end

  def self.post_individual_response(standup_response)
    chat = chat_for(standup_response)
    display_name = chat.display_name_for(standup_response.platform_user_id)
    answers = postable_answers(standup_response)
    return if answers.empty?

    # Keep the message ID so later edits can update the channel post in place.
    message = chat.post_standup_update(
      standup_response.standup.platform_channel,
      display_name: display_name,
      standup_name: standup_response.standup.name,
      answers: answers,
      edited: edited?(standup_response)
    )

    if message&.id.present?
      standup_response.platform_message_id = message.id
      standup_response.save!
    end
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
