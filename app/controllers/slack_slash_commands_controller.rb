class SlackSlashCommandsController < ApplicationController
  before_action :verify_slack_request
  before_action :require_user_id

  def standup
    render_reply command_handler.run(params[:text])
  end

  def standup_status
    render_reply command_handler.status
  end

  private

  def require_user_id
    render_ephemeral("Missing Slack user id.", status: :bad_request) if params[:user_id].blank?
  end

  def command_handler
    StandupCommandHandler.new(chat: chat, user_id: params[:user_id])
  end

  def chat
    ChatPlatform.for(:slack)
  end

  def render_reply(reply)
    return render_ephemeral(reply.text, status: reply.status) unless reply.selection?

    render json: {
      response_type: "ephemeral",
      text: reply.text,
      blocks: chat.selection_blocks(reply.text, reply.options, action_id: reply.action_id)
    }
  end

  def render_ephemeral(text, status: :ok)
    render json: {
      response_type: "ephemeral",
      text: text
    }, status: status
  end
end
