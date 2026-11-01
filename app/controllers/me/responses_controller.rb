module Me
  class ResponsesController < ApplicationController
    LIMIT = 30

    def index
      @standups = current_member.standups
      @standup = @standups.find { |standup| standup.id == params[:standup_id].to_i } if params[:standup_id].present?
      scope = current_member.responses
      scope = scope.where(standup_id: @standup.id) if @standup
      @responses = scope.order(standup_date: :desc, created_at: :desc).limit(LIMIT).to_a
    end
  end
end
