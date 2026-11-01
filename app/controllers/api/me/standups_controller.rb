module Api
  module Me
    # The signed-in member's own standups. Members only ever see their own data,
    # so the token (which has no member identity) is refused.
    class StandupsController < BaseController
      before_action :require_member!

      def index
        summaries = current_member.participants.map { |participant| MemberStandupSummary.new(participant) }
        render json: MemberStandupsSerializer.new(current_member, summaries).as_json
      end
    end
  end
end
