class SlackEventsController < ApplicationController
  SLACK_CHALLENGE_PATTERN = /\A[\w-]{1,256}\z/
  MAX_INTERACTION_PAYLOAD_BYTES = 100.kilobytes

  before_action :verify_slack_request

  def install
    head :no_content
  end

  def interactions
    Rails.logger.info "Received Slack interaction payload"

    payload = parse_interaction_payload
    return if performed?

    case payload["type"]
    when "block_actions"
      handle_block_actions(payload)
    when "view_submission"
      head :ok
    else
      Rails.logger.info "Ignoring unsupported Slack interaction type=#{payload['type']}"
      head :ok
    end
  end

  def events
    # Handle URL verification challenge from Slack
    if params[:type] == "url_verification"
      Rails.logger.info "Handling Slack URL verification challenge"
      challenge = params[:challenge].to_s

      unless valid_slack_challenge?(challenge)
        Rails.logger.warn "Rejected Slack URL verification challenge: invalid challenge format"
        head :bad_request
        return
      end

      render json: { challenge: challenge }
      return
    end

    event_type = event_params[:type]
    subtype = event_params[:subtype]
    user_id = event_params[:user] || event_params.dig(:message, :user)
    channel = event_params[:channel]

    Rails.logger.info "Received Slack event=#{event_type} subtype=#{subtype} from user=#{user_id} in channel=#{channel}"

    # Process the event asynchronously
    SlackEventProcessorJob.perform_later(event_params.to_h)

    # Acknowledge receipt right away (Slack expects a quick response)
    head :ok
  end

  private

  def valid_slack_challenge?(challenge)
    SLACK_CHALLENGE_PATTERN.match?(challenge)
  end

  def event_params
    # Allow deeper nested parameters for message_changed events
    params.require(:event).permit(
      :type, :user, :text, :channel, :ts, :subtype,
      message: [ :type, :user, :text, :ts, :edited, { edited: [ :user, :ts ] } ],
      previous_message: [ :type, :user, :text, :ts, :edited, { edited: [ :user, :ts ] } ]
    )
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

  def handle_block_actions(payload)
    action = Array(payload["actions"]).first

    if action.blank?
      render_interaction_response("No Slack action was provided.")
      return
    end

    case action["action_id"]
    when "standup_selection"
      handle_standup_report_selection(payload, action)
    when "standup_start_selection"
      handle_standup_start_selection(payload, action)
    else
      Rails.logger.info "Ignoring unsupported Slack action_id=#{action['action_id']}"
      render_interaction_response("That Slack action is not supported yet.")
    end
  end

  def handle_standup_report_selection(payload, action)
    standup = selected_standup(action)
    participant = selected_participant(payload, standup)
    return render_interaction_response("I couldn't find that standup.") unless standup
    return render_interaction_response("You are not a participant in that standup.") unless participant

    StandupCollectionJob.perform_later(*standup_collection_args(participant))

    render_interaction_response(
      "Generating report for #{standup.name}. It will be posted to ##{standup.slack_channel} shortly."
    )
  end

  def handle_standup_start_selection(payload, action)
    standup = selected_standup(action)
    participant = selected_participant(payload, standup)
    user_id = payload.dig("user", "id")

    return render_interaction_response("I couldn't find that standup.") unless standup
    return render_interaction_response("You are not a participant in that standup.") unless participant

    StandupMessageJob.perform_later(user_id, standup.id, participant.standup_date_for(Time.current).iso8601)

    render_interaction_response("Starting #{standup.name} now. Check your DMs.")
  end

  def selected_standup(action)
    standup_id = action.dig("selected_option", "value") || action["value"]
    Standup.find_by(id: standup_id)
  end

  def selected_participant(payload, standup)
    user_id = payload.dig("user", "id")
    return if user_id.blank? || standup.blank?

    standup.standup_participants.find_by(slack_id: user_id, active: true)
  end

  def standup_collection_args(participant)
    [
      participant.standup_id,
      participant.standup_date_for(Time.current).iso8601,
      participant.standup_time_zone.tzinfo.name
    ]
  end

  def render_interaction_response(text)
    render json: {
      response_type: "ephemeral",
      replace_original: false,
      text: text
    }
  end
end
