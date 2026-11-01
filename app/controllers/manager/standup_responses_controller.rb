module Manager
  class StandupResponsesController < ApplicationController
    before_action :set_standup

    def index
      @history = StandupResponseHistory.new(standup: @standup, params: response_history_params)
      @avatar_urls = @standup.standup_participants.pluck(:platform_user_id, :avatar_url).to_h
    end

    private

    def set_standup
      @standup = Standup.find(params[:standup_id])
      authorize_standup!(@standup)
    end

    def response_history_params
      params.permit(:start_date, :end_date, :participant, :question)
    end
  end
end
