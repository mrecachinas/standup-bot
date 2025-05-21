class SlackEventsController < ApplicationController
  before_action :verify_slack_request, except: [ :install ]

  def install
  end

  def events
    # Handle URL verification challenge from Slack
    if params[:type] == "url_verification"
      Rails.logger.info "Handling Slack URL verification challenge"
      render json: { challenge: params[:challenge] }
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

  def event_params
    # Allow deeper nested parameters for message_changed events
    params.require(:event).permit(
      :type, :user, :text, :channel, :ts, :subtype,
      message: [ :type, :user, :text, :ts, :edited, { edited: [ :user, :ts ] } ],
      previous_message: [ :type, :user, :text, :ts, :edited, { edited: [ :user, :ts ] } ]
    )
  end

  def verify_slack_request
    timestamp = request.headers["X-Slack-Request-Timestamp"]
    signature = request.headers["X-Slack-Signature"]

    # Save the request body
    request.body.rewind
    body = request.body.read
    request.body.rewind  # Rewind so it can be read again later

    # Verify the request is from Slack
    unless SlackSignatureVerifier.verify(body, timestamp, signature)
      head :unauthorized
      return false  # This stops action execution when used in before_action
    end

    true  # This allows action execution to continue
  end
end
