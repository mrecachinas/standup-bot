class SlackInteractionProcessorJob < ApplicationJob
  queue_as :default

  def perform(payload)
    Rails.logger.info "Processing Slack interaction: #{payload['type']}"

    # Handle different types of interactions
    case payload["type"]
    when "block_actions"
      handle_block_actions(payload)
    when "view_submission"
      handle_view_submission(payload)
    else
      Rails.logger.warn "Unsupported interaction type: #{payload['type']}"
    end
  end

  private

  def handle_block_actions(payload)
    action = payload["actions"].first
    user_id = payload["user"]["id"]

    Rails.logger.info "Processing block action: #{action['action_id']} from user: #{user_id}"

    case action["action_id"]
    when "standup_completed"
      user = User.find_by(slack_id: user_id)
      standup_response = StandupResponse.find(action["value"])
      Rails.logger.info "Marking standup response #{standup_response.id} as completed for user #{user_id}"
      StandupResponseService.mark_completed(standup_response)
    else
      Rails.logger.warn "Unhandled block action: #{action['action_id']}"
    end
  end

  def handle_view_submission(payload)
    # Handle form submissions from modals
    submission = payload["view"]["state"]["values"]
    user_id = payload["user"]["id"]

    Rails.logger.info "Processing view submission from user: #{user_id}"

    # Process the submission values
    # ...
  end
end
