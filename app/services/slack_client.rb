class SlackClient
  MAX_RATE_LIMIT_RETRIES = 3

  def initialize
    Rails.logger.info "Initializing SlackClient"
    @client = Slack::Web::Client.new(token: slack_bot_token)
  end

  class << self
    # Provide a shared instance for the application
    def instance
      @instance ||= new
    end

    def reset!
      @instance = nil
    end

    def rotate_token!
      reset!
      Rails.application.config.slack = Rails.application.config_for(:slack)
      instance
    end
  end

  # Send standup questions to a user
  def send_standup_questions(slack_id, intro, questions)
    Rails.logger.info "Sending standup questions to user: #{slack_id}"
    first_question = questions.first

    # Use consistent formatting from the formatter
    formatted_question = StandupFormatter.format_question(first_question, 1, questions.size)

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
          text: formatted_question
        }
      }
    ]

    Rails.logger.debug "Sending message with #{blocks.size} blocks"

    response = with_rate_limit_handling("send_standup_questions") do
      @client.chat_postMessage(
        channel: slack_id,
        blocks: blocks,
        text: "Time for your daily standup!",
        as_user: true
      )
    end

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
    Rails.logger.debug "Message text present: #{text.present?}"
    Rails.logger.debug "Using blocks: #{blocks ? 'yes' : 'no'}"

    begin
      response = with_rate_limit_handling("send_message") do
        if blocks
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
      end

      Rails.logger.info "Successfully sent message to channel: #{channel}"
      StandupMetrics.track("slack.message_sent", channel: channel, blocks: blocks.present?)
      normalize_message_response(response)
    rescue => e
      Rails.logger.error "Error sending Slack message: #{e.class} - #{e.message}"
      StandupMetrics.track("slack.message_failed", channel: channel, error_class: e.class.name)
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
    response = with_rate_limit_handling("get_user_info") do
      @client.users_info(user: slack_id)
    end
    user = response.user
    Rails.logger.info "Successfully retrieved info for user: #{user&.name || slack_id}"

    # Return a hash with user data instead of the full user object
    {
      "name" => user.name,
      "tz" => user.tz,
      "tz_offset" => user.tz_offset,
      "profile" => user.profile
    }
  rescue Slack::Web::Api::Errors::UserNotFound
    Rails.logger.error "User not found in Slack: #{slack_id}"
    nil
  rescue Slack::Web::Api::Errors::TooManyRequestsError
    raise
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

    response = with_rate_limit_handling("send_standup_selection") do
      @client.chat_postMessage(
        channel: channel,
        blocks: blocks,
        text: text,
        as_user: true
      )
    end

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

    response = with_rate_limit_handling("send_standup_summary") do
      @client.chat_postMessage(
        channel: channel,
        blocks: blocks,
        text: "Daily Standup Summary",
        as_user: true
      )
    end

    Rails.logger.info "Successfully sent standup summary to channel: #{channel}"
    response
  end

  # Update an existing message in a channel
  def update_message(channel, message_ts, text, blocks = nil)
    Rails.logger.info "Updating message with timestamp #{message_ts} in channel: #{channel}"

    begin
      response = with_rate_limit_handling("update_message") do
        if blocks
          Rails.logger.debug "Updating message with blocks"
          @client.chat_update(
            channel: channel,
            ts: message_ts,
            blocks: blocks,
            text: text, # Fallback text
            as_user: true
          )
        else
          Rails.logger.debug "Updating message with simple text"
          @client.chat_update(
            channel: channel,
            ts: message_ts,
            text: text,
            as_user: true
          )
        end
      end

      Rails.logger.info "Successfully updated message in channel: #{channel}"
      response
    rescue => e
      Rails.logger.error "Error updating Slack message: #{e.class} - #{e.message}"
      raise
    end
  end

  private

  def slack_bot_token
    slack_config = Rails.application.config.slack || {}
    token = slack_config[:bot_token] || slack_config["bot_token"]
    Rails.logger.warn "Slack bot token is not configured" if token.blank?
    token
  end

  def with_rate_limit_handling(operation)
    retries = 0

    begin
      yield
    rescue Slack::Web::Api::Errors::TooManyRequestsError => e
      StandupMetrics.track("slack.rate_limited", operation: operation)

      if retries < MAX_RATE_LIMIT_RETRIES
        retry_after = retry_after_seconds(e, retries)
        retries += 1
        Rails.logger.warn "Slack API rate limited during #{operation}; retrying #{retries}/#{MAX_RATE_LIMIT_RETRIES} after #{retry_after}s"
        sleep retry_after
        retry
      end

      Rails.logger.error "Slack API rate limit retries exhausted during #{operation}"
      raise
    end
  end

  def retry_after_seconds(error, retries)
    retry_after = error.retry_after if error.respond_to?(:retry_after)
    if retry_after.blank? && error.respond_to?(:response)
      retry_after = error.response&.headers&.[]("retry-after") ||
        error.response&.headers&.[]("Retry-After")
    end

    retry_after.to_i.positive? ? retry_after.to_i : (2**retries)
  end

  def normalize_message_response(response)
    return response if response.blank?

    {
      "ok" => response_value(response, "ok"),
      "channel" => response_value(response, "channel"),
      "ts" => response_value(response, "ts")
    }.compact
  end

  def response_value(response, key)
    response[key] || response[key.to_sym]
  rescue NoMethodError
    response.public_send(key) if response.respond_to?(key)
  end
end
