class SlackEventsController < ApplicationController
  SLACK_CHALLENGE_PATTERN = /\A[\w-]{1,256}\z/
  MAX_INTERACTION_PAYLOAD_BYTES = 100.kilobytes

  before_action :verify_slack_request

  def install
    head :no_content
  end

  def interactions
    payload = parse_interaction_payload
    return if performed?

    response = SlackInbound.interaction(payload)
    return head :ok unless response

    render json: response.body, status: response.status
  end

  def events
    if params[:type] == "url_verification"
      challenge = params[:challenge].to_s

      unless valid_slack_challenge?(challenge)
        Rails.logger.warn "Rejected Slack URL verification challenge: invalid challenge format"
        head :bad_request
        return
      end

      render json: { challenge: challenge }
      return
    end

    SlackInbound.enqueue_event(params.require(:event))

    # Slack retries events that aren't acknowledged within 3 seconds.
    head :ok
  end

  private

  def valid_slack_challenge?(challenge)
    SLACK_CHALLENGE_PATTERN.match?(challenge)
  end

  def parse_interaction_payload
    raw_payload = params.require(:payload).to_s
    if raw_payload.bytesize > MAX_INTERACTION_PAYLOAD_BYTES
      Rails.logger.warn "Received oversized Slack interaction payload"
      render json: {
        response_type: "ephemeral",
        text: "Sorry, that Slack interaction payload is too large."
      }, status: :bad_request
      return nil
    end

    parsed_payload = JSON.parse(raw_payload)
    return parsed_payload if parsed_payload.is_a?(Hash)

    raise JSON::ParserError, "payload must be a JSON object"
  rescue ActionController::ParameterMissing, JSON::ParserError
    Rails.logger.warn "Received invalid Slack interaction payload"
    render json: {
      response_type: "ephemeral",
      text: "Sorry, I couldn't understand that Slack interaction."
    }, status: :bad_request
    nil
  end
end
