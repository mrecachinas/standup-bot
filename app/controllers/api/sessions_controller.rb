module Api
  # The console's bootstrap and access-token sign-in. Slack and Microsoft
  # sign-in stay as server-side redirects under /auth.
  class SessionsController < BaseController
    skip_before_action :authenticate!, only: [ :show, :create ]
    before_action :require_session!
    before_action :skip_authorization

    def show
      render json: bootstrap_payload
    end

    def create
      user = User.authenticate(params[:email], params[:access_token])

      unless user
        render json: { error: "That email and access token don't match an active account." }, status: :unauthorized
        return
      end

      reset_session
      session[:user_id] = user.id
      user.update!(last_signed_in_at: Time.current)
      @current_user = user
      render json: bootstrap_payload, status: :created
    end

    def destroy
      reset_session
      @current_user = nil
      @current_member = nil
      render json: bootstrap_payload
    end

    private

    def bootstrap_payload
      {
        authenticated: current_user.present? || current_member.present?,
        user: current_user && serialize_user(current_user),
        member: current_member && serialize_member(current_member),
        sidebar_standups: sidebar_standups,
        platforms: PlatformSerializer.all,
        csrf_token: form_authenticity_token,
        flash: flash.map { |type, message| { type: flash_tone(type), message: message } if message.present? }.compact,
        dev_prefill: dev_prefill
      }
    end

    def serialize_user(user)
      {
        id: user.id,
        name: user.name,
        email: user.email,
        role: user.role,
        admin: user.admin?,
        avatar_url: user.avatar_url
      }
    end

    def serialize_member(member)
      {
        platform: member.platform,
        platform_user_id: member.platform_user_id,
        name: member.name,
        avatar_url: member.avatar_url
      }
    end

    def sidebar_standups
      return [] unless current_user

      Standup.manageable_by(current_user).order(:name).select(:id, :name, :active).map do |standup|
        { id: standup.id, name: standup.name, active: standup.active? }
      end
    end

    def flash_tone(type)
      { "notice" => "success", "alert" => "danger" }.fetch(type.to_s, "warning")
    end

    def dev_prefill
      return unless Rails.env.development?

      email = ENV["MANAGER_ADMIN_EMAIL"].presence
      access_token = ENV["MANAGER_ADMIN_TOKEN"].presence
      { email: email, access_token: access_token } if email || access_token
    end
  end
end
