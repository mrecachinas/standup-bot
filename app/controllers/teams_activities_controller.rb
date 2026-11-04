# Receives Teams activities from the Bot Connector. Every request must carry a
# valid Bot Framework token, and the work happens in TeamsActivityProcessorJob.
class TeamsActivitiesController < ApplicationController
  MAX_ACTIVITY_BYTES = 256.kilobytes
  ACTIVITY_KEYS = %w[type id timestamp text value serviceUrl channelId from conversation channelData recipient replyToId].freeze

  def create
    return head(:content_too_large) if request.raw_post.bytesize > MAX_ACTIVITY_BYTES

    activity = parse_activity
    return head(:bad_request) unless activity

    Microsoft::BotFrameworkAuth.new.verify!(
      request.authorization,
      service_url: activity["serviceUrl"],
      channel_id: activity["channelId"]
    )

    return head(:ok) unless activity["channelId"] == "msteams"
    return head(:forbidden) unless expected_tenant?(activity)

    TeamsActivityProcessorJob.perform_later(activity.slice(*ACTIVITY_KEYS))
    head :ok
  rescue Microsoft::BotFrameworkAuth::Unauthorized => error
    Rails.logger.warn "Rejected Teams activity: #{error.message}"
    head :unauthorized
  end

  private

  def parse_activity
    activity = JSON.parse(request.raw_post)
    activity if activity.is_a?(Hash)
  rescue JSON::ParserError
    nil
  end

  def expected_tenant?(activity)
    tenant = activity.dig("conversation", "tenantId").presence || activity.dig("channelData", "tenant", "id")
    tenant.present? && tenant == Microsoft::Config.tenant_id
  end
end
