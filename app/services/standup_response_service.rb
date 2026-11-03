class StandupResponseService
  SKIPPED_ANSWER = "(skipped)".freeze

  def self.chat_for(standup_response)
    ChatPlatform.for_standup(standup_response.standup)
  end

  def self.record_answer(standup_response, text)
    answer_text = normalize_answer_text(text)
    return skip_question(standup_response) if answer_text.strip.downcase == "skip"

    append_answer(standup_response, answer_text)
    process_answer_update(standup_response)
  end

  def self.skip_question(standup_response)
    append_answer(standup_response, SKIPPED_ANSWER)
    process_answer_update(standup_response)
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

  def self.append_answer(standup_response, answer_text)
    standup_response.answers ||= []
    standup_response.answers << {
      question: standup_response.standup.questions[standup_response.answers.size],
      answer: answer_text,
      timestamp: Time.current
    }
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
    answers = postable_answers(standup_response)
    return if answers.empty?

    chat.update_standup_update(
      standup_response.standup.platform_channel,
      message_id,
      display_name: display_name,
      standup_name: standup_response.standup.name,
      answers: answers
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
      answers: answers
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
end
