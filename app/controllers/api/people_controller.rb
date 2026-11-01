module Api
  # Person search for the console's people picker, against the chat platform
  # the standup uses.
  class PeopleController < BaseController
    DEFAULT_LIMIT = 20

    before_action :require_manager!
    before_action :skip_authorization

    def index
      platform = params[:platform].presence || ChatPlatform::DEFAULT.to_s
      unless ChatPlatform.supported?(platform)
        render json: { error: "Unknown chat platform: #{platform}" }, status: :unprocessable_entity
        return
      end

      limit = params.fetch(:limit, DEFAULT_LIMIT).to_i.clamp(1, ChatIntegrationService::MAX_LIMIT)
      result = ChatIntegrationService.for(platform).discover_users(query: params[:q].to_s.strip.presence, limit: limit)

      render json: {
        platform: platform.to_s,
        people: Array(result.records).first(limit).map { |record| person_json(record) },
        success: result.success?,
        message: result.message
      }
    end

    private

    def person_json(record)
      avatar_url = record["avatar_url"]
      {
        platform_user_id: record["id"],
        display_name: record["label"].presence || record["display_name"].presence || record["real_name"].presence || record["name"].presence || record["id"],
        avatar_url: (avatar_url if SlackAvatar.safe_url?(avatar_url)),
        timezone: record["tz"].presence || record["timezone"].presence
      }
    end
  end
end
