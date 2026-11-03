class SlackSlashCommandsController < ApplicationController
  before_action :verify_slack_request

  def standup
    render_response SlackInbound.slash_command(:standup, user_id: params[:user_id], text: params[:text])
  end

  def standup_status
    render_response SlackInbound.slash_command(:standup_status, user_id: params[:user_id])
  end

  private

  def render_response(response)
    render json: response.body, status: response.status
  end
end
