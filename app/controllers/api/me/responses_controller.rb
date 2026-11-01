module Api
  module Me
    # The signed-in member's most recent check-ins, optionally for one standup.
    class ResponsesController < BaseController
      LIMIT = 30

      before_action :require_member!

      def index
        standups = current_member.standups
        standup = standups.find { |candidate| candidate.id == params[:standup_id].to_i } if params[:standup_id].present?
        scope = current_member.responses
        scope = scope.where(standup_id: standup.id) if standup
        responses = scope.order(standup_date: :desc, created_at: :desc).limit(LIMIT).to_a

        render json: MemberResponsesSerializer.new(current_member, standups: standups, standup: standup, responses: responses, limit: LIMIT).as_json
      end
    end
  end
end
