class StandupResponseService
  def self.slack_client
    SlackClient.instance
  end

  def self.record_answer(standup_response, text)
    Rails.logger.info "Recording answer for standup response #{standup_response.id} from user #{standup_response.slack_id}"
    answer_text = normalize_answer_text(text)

    # Check for skip command
    if answer_text.strip.downcase == "skip"
      Rails.logger.info "User requested to skip the question"
      return skip_question(standup_response)
    end

    # Get the current question and standup
    standup = standup_response.standup
    current_question_idx = standup_response.answers&.size || 0
    Rails.logger.info "Processing answer for question #{current_question_idx + 1}/#{standup.questions.size}"

    # If no answers yet, initialize the array
    standup_response.answers ||= []

    # Add the answer
    standup_response.answers << {
      question: standup.questions[current_question_idx],
      answer: answer_text,
      timestamp: Time.current
    }
    Rails.logger.debug "Answer recorded for question #{current_question_idx + 1}"

    # Process the updated standup response
    process_answer_update(standup_response)

    Rails.logger.info "Standup response #{standup_response.id} saved successfully"
  end

  def self.skip_question(standup_response)
    Rails.logger.info "Skipping question for standup response #{standup_response.id}"

    # Get the current question and standup
    standup = standup_response.standup
    current_question_idx = standup_response.answers&.size || 0
    Rails.logger.info "Skipping question #{current_question_idx + 1}/#{standup.questions.size}"

    # If no answers yet, initialize the array
    standup_response.answers ||= []

    # Add a skipped answer
    standup_response.answers << {
      question: standup.questions[current_question_idx],
      answer: "(skipped)",
      timestamp: Time.current
    }
    Rails.logger.debug "Question #{current_question_idx + 1} marked as skipped"

    # Process the updated standup response
    process_answer_update(standup_response)

    Rails.logger.info "Standup response #{standup_response.id} saved successfully after skip"
  end

  def self.skip_remaining_questions(standup_response, notify: true)
    Rails.logger.info "Skipping remaining questions for standup response #{standup_response.id}"

    standup = standup_response.standup
    standup_response.answers ||= []

    while standup_response.answers.size < standup.questions.size
      current_question_idx = standup_response.answers.size
      standup_response.answers << {
        question: standup.questions[current_question_idx],
        answer: "(skipped)",
        timestamp: Time.current
      }
    end

    standup_response.status = "skipped"
    standup_response.save!

    if notify
      slack_client.send_message(
        standup_response.slack_id,
        "Your remaining #{standup.name} standup questions have been skipped."
      )
    end

    Rails.logger.info "Standup response #{standup_response.id} marked as skipped"
  end

  def self.mark_completed(standup_response)
    Rails.logger.info "Manually marking standup response #{standup_response.id} as completed"
    complete_standup_response(standup_response)
    standup_response.save!
    Rails.logger.info "Standup response #{standup_response.id} completed"
  end

  def self.cancel_previous_pending_responses(slack_id, standup_id, current_standup_date = nil, timezone = Time.zone)
    Rails.logger.info "Canceling previous pending responses for user #{slack_id} in standup #{standup_id}"
    zone = Standup.resolve_time_zone(timezone)
    standup_date = current_standup_date.present? ? StandupResponse.normalize_date(current_standup_date) : zone.today
    day_start = zone.local(standup_date.year, standup_date.month, standup_date.day)

    # Find all pending responses for this user in this standup that are from previous days
    previous_pending = StandupResponse
      .where(slack_id: slack_id, standup_id: standup_id, status: "pending")
      .where(
        "standup_date < :standup_date OR (standup_date IS NULL AND created_at < :day_start)",
        standup_date: standup_date,
        day_start: day_start
      )

    return if previous_pending.empty?

    Rails.logger.info "Found #{previous_pending.count} previous pending responses to cancel"

    previous_pending.each do |response|
      Rails.logger.info "Canceling standup response #{response.id} from #{response.created_at.strftime('%Y-%m-%d')}"
      response.update!(status: "skipped")
    end

    Rails.logger.info "Successfully canceled #{previous_pending.count} previous pending responses"
  end

  def self.normalize_answer_text(text)
    normalized_text = text.to_s
    return normalized_text if normalized_text.length <= StandupResponse::MAX_ANSWER_LENGTH

    Rails.logger.warn "Answer exceeds maximum length; truncating to #{StandupResponse::MAX_ANSWER_LENGTH} characters"
    normalized_text.truncate(StandupResponse::MAX_ANSWER_LENGTH, omission: "")
  end

  # Helper method to process answer updates and determine next steps
  def self.process_answer_update(standup_response)
    standup = standup_response.standup

    # Check if all questions have been answered
    if standup_response.answers.size >= standup.questions.size
      # All questions answered, mark as complete
      Rails.logger.info "All questions have been answered, completing standup response"
      complete_standup_response(standup_response)
    else
      # Send the next question
      Rails.logger.info "Sending next question #{standup_response.answers.size + 1}/#{standup.questions.size}"
      send_next_question(standup_response)
    end

    standup_response.save!
  end

  # Update an existing standup response in the channel
  def self.repost_response(standup_response)
    Rails.logger.info "Updating standup response #{standup_response.id} in channel"
    standup = standup_response.standup

    # Get the message timestamp
    message_ts = standup_response.slack_message_ts

    if message_ts.present?
      # Format the updated response
      # Get user info for the display name
      user_info = slack_client.get_user_info(standup_response.slack_id)
      display_name = user_info&.dig("profile", "display_name") || user_info&.dig("name") || "Unknown User"

      # Format the responses
      formatted_responses = []
      standup_response.answers.each do |answer|
        # Skip empty answers
        next if answer["answer"].blank? || answer["answer"] == "(skipped)"

        formatted_responses << "*#{answer["question"]}*\n#{answer["answer"]}"
      end

      # No need to update if all questions were skipped
      if formatted_responses.empty?
        Rails.logger.info "All questions were skipped, not updating message"
        return
      end

      # Build the message with user information
      message = [
        "*#{display_name}'s Standup Update:*",
        "",
        formatted_responses.join("\n\n")
      ].join("\n")

      # Create blocks for formatting (same structure as in post_individual_response)
      blocks = [
        {
          type: "section",
          text: {
            type: "mrkdwn",
            text: "*#{display_name}'s Standup Update:*"
          }
        }
      ]

      # Add each formatted response as a section
      formatted_responses.each do |response_text|
        blocks << {
          type: "section",
          text: {
            type: "mrkdwn",
            text: response_text
          }
        }
      end

      # Update the existing message
      Rails.logger.info "Updating message with timestamp #{message_ts} in channel #{standup.slack_channel}"
      slack_client.update_message(standup.slack_channel, message_ts, message, blocks)
      Rails.logger.info "Successfully updated standup response in channel #{standup.slack_channel}"
    else
      # If we don't have a stored message timestamp, post as a new message
      Rails.logger.info "No stored message timestamp, posting as a new message"
      post_individual_response(standup_response)
    end
  end

  private

  def self.complete_standup_response(standup_response)
    Rails.logger.info "Completing standup response #{standup_response.id}"
    standup = standup_response.standup
    standup_response.status = "completed"

    # Send a completion message to the user with the outro if provided
    completion_message = if standup.outro.present?
      "#{standup.outro}\n\nYour standup update has been posted to ##{standup.slack_channel}."
    else
      "Thank you! Your standup update has been posted to ##{standup.slack_channel}."
    end

    Rails.logger.info "Sending completion message to user #{standup_response.slack_id}"
    slack_client.send_message(
      standup_response.slack_id,
      completion_message
    )

    # Post the individual's response to the channel immediately
    Rails.logger.info "Posting individual response to channel ##{standup.slack_channel}"
    post_individual_response(standup_response)

    # Check if all participants have completed their standups
    Rails.logger.info "Checking if all standup responses are complete"
    check_if_all_responses_complete(standup, standup_response.standup_date, response_time_zone_for(standup_response))
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
    Rails.logger.info "Sending next question for standup response #{standup_response.id}"
    standup = standup_response.standup
    current_question_idx = standup_response.answers.size
    next_question = standup.questions[current_question_idx]

    # Format the question with a counter
    question_number = current_question_idx + 1
    total_questions = standup.questions.size
    formatted_question = StandupFormatter.format_question(next_question, question_number, total_questions)
    Rails.logger.debug "Formatted question #{question_number}/#{total_questions}"

    # Send the next question
    Rails.logger.info "Sending question to user #{standup_response.slack_id}"
    slack_client.send_message(
      standup_response.slack_id,
      formatted_question
    )
  end

  def self.post_individual_response(standup_response)
    Rails.logger.info "Posting individual response for standup response #{standup_response.id}"
    standup = standup_response.standup

    # Get user info for the display name
    Rails.logger.info "Fetching user info for user #{standup_response.slack_id}"
    user_info = slack_client.get_user_info(standup_response.slack_id)
    display_name = user_info&.dig("profile", "display_name") || user_info&.dig("name") || "Unknown User"
    Rails.logger.info "Resolved display name: #{display_name}"

    # Format the responses
    formatted_responses = []
    standup_response.answers.each do |answer|
      # Skip empty answers
      next if answer["answer"].blank? || answer["answer"] == "(skipped)"

      formatted_responses << "*#{answer["question"]}*\n#{answer["answer"]}"
    end

    # No need to post if all questions were skipped
    if formatted_responses.empty?
      Rails.logger.info "All questions were skipped, not posting any responses"
      return
    end

    # Build the message with user information
    message = [
      "*#{display_name}'s Standup Update:*",
      "",
      formatted_responses.join("\n\n")
    ].join("\n")

    Rails.logger.info "Posting formatted response with #{formatted_responses.size} answers"

    # Post to the channel and store the message timestamp for potential future updates
    response = slack_client.send_message(standup.slack_channel, message)

    # Store the message timestamp in the standup_response for future reference
    if response && response["ts"]
      standup_response.slack_message_ts = response["ts"]
      standup_response.save!
      Rails.logger.info "Saved message timestamp #{response['ts']} to standup_response #{standup_response.id}"
    end

    Rails.logger.info "Successfully posted response to channel ##{standup.slack_channel}"
  end

  def self.check_if_all_responses_complete(standup, standup_date = nil, timezone = Time.zone)
    Rails.logger.info "Checking completion status for standup #{standup.id} - #{standup.name}"
    zone = Standup.resolve_time_zone(timezone)
    response_date = standup_date || zone.today

    # Count active participants
    total_participants = standup.standup_participants.active.select { |participant| participant.available_on?(response_date) }.count
    Rails.logger.info "Total active participants: #{total_participants}"

    # Count completed responses for the same standup date
    completed_responses = StandupResponse
      .where(standup_id: standup.id, status: "completed")
      .for_date_in_timezone(response_date, zone)
      .count

    Rails.logger.info "Completed responses today: #{completed_responses}/#{total_participants}"

    # No need for a summary if individual responses are already posted
    # But you could still schedule one if needed
    # if completed_responses >= total_participants
    #   Rails.logger.info "All responses complete, scheduling summary collection"
    #   StandupCollectionJob.set(wait: 2.minutes).perform_later(standup.id)
    # end
  end

  def self.response_time_zone_for(standup_response)
    standup_response.participant&.standup_time_zone || Time.zone
  end
end
