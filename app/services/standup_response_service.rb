class StandupResponseService
  def self.slack_client
    SlackClient.instance
  end

  def self.record_answer(standup_response, text)
    answer_text = normalize_answer_text(text)
    return skip_question(standup_response) if answer_text.strip.downcase == "skip"

    append_answer(standup_response, answer_text)
    process_answer_update(standup_response)
  end

  def self.skip_question(standup_response)
    append_answer(standup_response, "(skipped)")
    process_answer_update(standup_response)
  end

  def self.skip_remaining_questions(standup_response, notify: true)
    standup = standup_response.standup
    standup_response.answers ||= []

    while standup_response.answers.size < standup.questions.size
      append_answer(standup_response, "(skipped)")
    end

    standup_response.status = "skipped"
    standup_response.save!

    if notify
      slack_client.send_message(
        standup_response.slack_id,
        "Your remaining #{standup.name} standup questions have been skipped."
      )
    end
  end

  def self.mark_completed(standup_response)
    complete_standup_response(standup_response)
    standup_response.save!
  end

  def self.cancel_previous_pending_responses(slack_id, standup_id, current_standup_date = nil, timezone = Time.zone)
    zone = Standup.resolve_time_zone(timezone)
    standup_date = current_standup_date.present? ? StandupResponse.normalize_date(current_standup_date) : zone.today
    day_start = zone.local(standup_date.year, standup_date.month, standup_date.day)

    previous_pending = StandupResponse
      .where(slack_id: slack_id, standup_id: standup_id, status: "pending")
      .where(
        "standup_date < :standup_date OR (standup_date IS NULL AND created_at < :day_start)",
        standup_date: standup_date,
        day_start: day_start
      )

    previous_pending.each { |response| response.update!(status: "skipped") }
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
    message_ts = standup_response.slack_message_ts
    return post_individual_response(standup_response) if message_ts.blank?

    display_name = display_name_for(standup_response.slack_id)
    formatted_responses = formatted_answers(standup_response)
    return if formatted_responses.empty?

    blocks = [ "*#{display_name}'s Standup Update:*", *formatted_responses ].map do |text|
      { type: "section", text: { type: "mrkdwn", text: text } }
    end

    slack_client.update_message(
      standup_response.standup.slack_channel,
      message_ts,
      response_message(display_name, formatted_responses),
      blocks
    )
  end

  def self.complete_standup_response(standup_response)
    standup = standup_response.standup
    standup_response.status = "completed"

    completion_message = if standup.outro.present?
      "#{standup.outro}\n\nYour standup update has been posted to ##{standup.slack_channel}."
    else
      "Thank you! Your standup update has been posted to ##{standup.slack_channel}."
    end
    slack_client.send_message(standup_response.slack_id, completion_message)

    post_individual_response(standup_response)

    StandupMetrics.track(
      "standup.completed",
      standup_id: standup.id,
      slack_id: standup_response.slack_id,
      response_id: standup_response.id,
      duration_seconds: response_duration_seconds(standup_response)
    )
  end

  def self.response_duration_seconds(standup_response)
    return unless standup_response.created_at

    (Time.current - standup_response.created_at).round
  end

  def self.send_next_question(standup_response)
    standup = standup_response.standup
    current_question_idx = standup_response.answers.size
    formatted_question = StandupFormatter.format_question(
      standup.questions[current_question_idx],
      current_question_idx + 1,
      standup.questions.size
    )

    slack_client.send_message(standup_response.slack_id, formatted_question)
  end

  def self.post_individual_response(standup_response)
    display_name = display_name_for(standup_response.slack_id)
    formatted_responses = formatted_answers(standup_response)
    return if formatted_responses.empty?

    # Keep the message ts so later edits can update the channel post in place.
    response = slack_client.send_message(
      standup_response.standup.slack_channel,
      response_message(display_name, formatted_responses)
    )

    if response && response["ts"]
      standup_response.slack_message_ts = response["ts"]
      standup_response.save!
    end
  end

  def self.display_name_for(slack_id)
    user_info = slack_client.get_user_info(slack_id)
    user_info&.dig("profile", "display_name") || user_info&.dig("name") || "Unknown User"
  end

  def self.formatted_answers(standup_response)
    standup_response.answers.filter_map do |answer|
      next if answer["answer"].blank? || answer["answer"] == "(skipped)"

      "*#{answer["question"]}*\n#{answer["answer"]}"
    end
  end

  def self.response_message(display_name, formatted_responses)
    [
      "*#{display_name}'s Standup Update:*",
      "",
      formatted_responses.join("\n\n")
    ].join("\n")
  end
end
