class SlackEventsController < ApplicationController
  skip_before_action :verify_authenticity_token
  before_action :verify_slack_request, except: [ :install ]

  def events
    # Handle URL verification challenge from Slack
    if params[:type] == "url_verification"
      Rails.logger.info "Handling Slack URL verification challenge"
      render json: { challenge: params[:challenge] }
      return
    end

    Rails.logger.info "Received Slack event: #{params[:event][:type]} from user: #{params[:event][:user]} in channel: #{params[:event][:channel]}"

    # Process the event asynchronously
    SlackEventProcessorJob.perform_later(event_params.to_h)

    # Acknowledge receipt right away (Slack expects a quick response)
    head :ok
  end

  def interactions
    # Process interactive components (buttons, modals, etc.)
    payload = JSON.parse(params[:payload])
    Rails.logger.info "Received Slack interaction: #{payload['type']} from user: #{payload['user']['id']}"

    SlackInteractionProcessorJob.perform_later(payload)

    head :ok
  end

  private

  def event_params
    params.require(:event).permit(:type, :user, :text, :channel, :ts)
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
