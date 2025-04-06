class SlackClient
  def initialize
    Rails.logger.info "Initializing SlackClient"
    @client = Slack::Web::Client.new(token: Rails.application.config.slack[:bot_token])
  end

  # Send standup questions to a user
  def send_standup_questions(slack_id, intro, questions)
    Rails.logger.info "Sending standup questions to user: #{slack_id}"
    first_question = questions.first

    blocks = [
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: intro || "Time for your daily standup!"
        }
      },
      { type: "divider" },
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "*Question 1:* #{first_question}"
        }
      }
    ]

    Rails.logger.debug "Sending message with #{blocks.size} blocks"

    response = @client.chat_postMessage(
      channel: slack_id,
      blocks: blocks,
      text: "Time for your daily standup!",
      as_user: true
    )

    Rails.logger.info "Successfully sent standup questions to user: #{slack_id}, channel: #{response['channel']}"

    # Return channel and timestamp for tracking
    {
      channel: response["channel"],
      ts: response["ts"]
    }
  end

  # Send a simple text message
  def send_message(channel, text, blocks = nil)
    Rails.logger.info "Sending message to channel: #{channel}"
    Rails.logger.debug "Message text: #{text.truncate(50) if text}"
    Rails.logger.debug "Using blocks: #{blocks ? 'yes' : 'no'}"

    # Rate limiting with exponential backoff
    retries = 0
    begin
      response = if blocks
        Rails.logger.debug "Sending message with blocks"
        @client.chat_postMessage(
          channel: channel,
          blocks: blocks,
          text: text, # Fallback text
          as_user: true
        )
      else
        Rails.logger.debug "Sending simple text message"
        @client.chat_postMessage(
          channel: channel,
          text: text,
          as_user: true
        )
      end

      Rails.logger.info "Successfully sent message to channel: #{channel}"
      response
    rescue Slack::Web::Api::Errors::TooManyRequestsError => e
      # Get retry time from response header or use exponential backoff
      retry_after = e.response_metadata&.dig("retry_after") || (2**retries)
      Rails.logger.warn "Rate limited by Slack API. Retry after #{retry_after} seconds. Attempt #{retries + 1}/4"

      if retries < 3
        retries += 1
        sleep retry_after
        retry
      else
        Rails.logger.error "Failed to send Slack message after retries: #{e.message}"
        raise
      end
    rescue => e
      Rails.logger.error "Error sending Slack message: #{e.class} - #{e.message}"
      raise
    end
  end

  # Send a formatted message for standup responses
  def send_standup_response(channel, user_name, responses)
    Rails.logger.info "Sending formatted standup response for #{user_name} to channel: #{channel}"
    Rails.logger.debug "Response contains #{responses.size} answers"

    blocks = [
      {
        type: "header",
        text: {
          type: "plain_text",
          text: "#{user_name}'s Standup Update"
        }
      },
      { type: "divider" }
    ]

    # Add each Q&A as a section
    responses.each do |response|
      blocks << {
        type: "section",
        text: {
          type: "mrkdwn",
          text: "*#{response[:question]}*\n#{response[:answer]}"
        }
      }
    end

    result = send_message(channel, "#{user_name}'s Standup Update", blocks)
    Rails.logger.info "Successfully sent standup response for #{user_name}"
    result
  end

  # Get user info including timezone
  def get_user_info(slack_id)
    Rails.logger.info "Fetching user info for Slack ID: #{slack_id}"
    user = @client.users_info(user: slack_id)&.user
    Rails.logger.info "Successfully retrieved info for user: #{user&.name || slack_id}"
    user
  rescue Slack::Web::Api::Errors::UserNotFound
    Rails.logger.error "User not found in Slack: #{slack_id}"
    nil
  rescue => e
    Rails.logger.error "Error fetching user info: #{e.class} - #{e.message}"
    nil
  end

  # Send standup selection menu
  def send_standup_selection(channel, text, options)
    Rails.logger.info "Sending standup selection menu to channel: #{channel}"
    Rails.logger.debug "Options count: #{options.size}"

    blocks = [
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: text
        }
      },
      {
        type: "actions",
        elements: [
          {
            type: "static_select",
            placeholder: {
              type: "plain_text",
              text: "Select a standup"
            },
            action_id: "standup_selection",
            options: options.map do |option|
              {
                text: {
                  type: "plain_text",
                  text: option[:text]
                },
                value: option[:value].to_s
              }
            end
          }
        ]
      }
    ]

    response = @client.chat_postMessage(
      channel: channel,
      blocks: blocks,
      text: text,
      as_user: true
    )

    Rails.logger.info "Successfully sent standup selection menu to channel: #{channel}"
    response
  end

  # Post a standup summary to a channel
  def send_standup_summary(channel, summary_text, outro = nil)
    Rails.logger.info "Sending standup summary to channel: #{channel}"

    blocks = [
      {
        type: "header",
        text: {
          type: "plain_text",
          text: "Daily Standup Summary"
        }
      },
      { type: "divider" },
      {
        type: "section",
        text: {
          type: "mrkdwn",
          text: summary_text
        }
      }
    ]

    # Add outro if provided
    if outro.present?
      Rails.logger.debug "Adding outro to summary"
      blocks << {
        type: "section",
        text: {
          type: "mrkdwn",
          text: outro
        }
      }
    end

    response = @client.chat_postMessage(
      channel: channel,
      blocks: blocks,
      text: "Daily Standup Summary",
      as_user: true
    )

    Rails.logger.info "Successfully sent standup summary to channel: #{channel}"
    response
  end
end
