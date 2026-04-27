module Api
  class StandupResponsesController < BaseController
    before_action :set_standup

    def index
      responses = @standup.standup_responses.order(created_at: :desc)
      responses = responses.where(status: params[:status]) if params[:status].present?
      responses = responses.where(slack_id: params[:slack_id]) if params[:slack_id].present?
      responses = responses.where("created_at >= ?", parsed_time(params[:since])) if params[:since].present?
      responses = responses.where("created_at <= ?", parsed_time(params[:until])) if params[:until].present?

      render json: {
        responses: responses.limit(limit).map { |standup_response| serialize_response(standup_response) }
      }
    end

    private

    def set_standup
      @standup = Standup.find(params[:standup_id])
    end

    def limit
      requested_limit = params.fetch(:limit, 100).to_i
      requested_limit.clamp(1, 500)
    end

    def parsed_time(value)
      Time.zone.parse(value)
    rescue ArgumentError, TypeError
      raise ActionController::BadRequest, "Invalid timestamp: #{value}"
    end

    def serialize_response(standup_response)
      {
        id: standup_response.id,
        standup_id: standup_response.standup_id,
        slack_id: standup_response.slack_id,
        slack_channel: standup_response.slack_channel,
        status: standup_response.status,
        answers: standup_response.answers || [],
        answer_count: standup_response.answers&.size || 0,
        slack_message_ts: standup_response.slack_message_ts,
        created_at: standup_response.created_at&.iso8601,
        updated_at: standup_response.updated_at&.iso8601
      }
    end
  end
end
