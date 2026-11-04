# Posts a finished run's update to the standup's channel, or updates the post
# that's already there, from the answers as saved. It runs right after the last
# answer or an edit (perform_now) and again on retries (retry_on in
# ApplicationJob), so the post always shows the current answers.
#
# announce: also DM the person the sign-off, and where the update went, once
# it's posted, so they're never told it was posted when it wasn't.
class StandupUpdateJob < ApplicationJob
  queue_as :default

  # Channel problems a retry won't fix. The answers are saved either way.
  UNPOSTABLE_SLACK_ERRORS = %w[
    not_in_channel channel_not_found is_archived invalid_channel restricted_action
    ekm_access_denied team_access_not_granted
  ].freeze
  # The post was deleted (or can't be edited anymore), so post a new one.
  MISSING_POST_SLACK_ERRORS = %w[message_not_found cant_update_message edit_window_closed].freeze

  def perform(standup_response, announce: false)
    return unless standup_response.status == "completed"

    result = post(standup_response)
    announce_completion(standup_response, result) if announce
  rescue Slack::Web::Api::Errors::SlackError, Microsoft::ApiError => error
    raise unless unpostable?(error)

    report_unpostable(standup_response, error, announce: announce)
  end

  private

  def post(standup_response)
    StandupResponseService.repost_response(standup_response)
  rescue Slack::Web::Api::Errors::SlackError => error
    raise unless MISSING_POST_SLACK_ERRORS.include?(error.message) && standup_response.platform_message_id.present?

    Rails.logger.info "Standup update #{standup_response.platform_message_id} is gone (#{error.message}); posting it again"
    standup_response.update!(platform_message_id: nil)
    StandupResponseService.repost_response(standup_response)
  end

  def announce_completion(standup_response, result)
    standup = standup_response.standup
    chat = chat_for(standup)
    lines = [ standup.outro.presence || "Thanks! 🙌" ]
    if result == :posted
      lines << "Your update has been posted to #{chat.channel_mention(standup.platform_channel, name: standup.platform_channel_name)}."
    end
    message = chat.send_direct_message(standup_response.platform_user_id, lines.join("\n\n"))
    StandupResponseService.prompted!(standup_response, message)
  end

  def unpostable?(error)
    case error
    when Slack::Web::Api::Errors::SlackError then UNPOSTABLE_SLACK_ERRORS.include?(error.message)
    when Microsoft::ApiError then error.forbidden? || error.not_found?
    else false
    end
  end

  # Tells the person their answers are safe and why they weren't posted, and
  # the admins what to fix.
  def report_unpostable(standup_response, error, announce:)
    standup = standup_response.standup
    chat = chat_for(standup)
    channel = chat.channel_mention(standup.platform_channel, name: standup.platform_channel_name)
    Rails.logger.warn "Couldn't post standup response #{standup_response.id} to #{standup.platform_channel}: #{error.class} - #{error.message}"
    StandupMetrics.track("standup.post_failed", standup_id: standup.id, response_id: standup_response.id, error: error.message)

    lines = []
    lines << (standup.outro.presence || "Thanks! 🙌") if announce
    lines << "I couldn't post your update to #{channel} (#{error.message}), but your answers are saved. I've let the standup's admins know."
    message = chat.send_direct_message(standup_response.platform_user_id, lines.join("\n\n"))
    StandupResponseService.prompted!(standup_response, message) if announce
    notify_admin_channel(error, context: "#{standup.name}: couldn't post to #{standup.platform_channel}")
  end
end
