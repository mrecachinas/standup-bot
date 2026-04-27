module Manager
  class StandupManagersController < ApplicationController
    before_action :set_standup
    before_action :set_ownership, only: :destroy

    def create
      user = selected_user
      unless user
        redirect_to manager_standup_path(@standup, manager_error: "Choose an active user to grant access."), status: :see_other
        return
      end

      ownership = @standup.standup_ownerships.find_or_initialize_by(user: user)
      if ownership.persisted?
        redirect_to manager_standup_path(@standup, manager_notice: "#{user.name} already has manager access."), status: :see_other
        return
      end

      ownership.role = "manager"
      ownership.save!
      audit_manager_change!("standup_manager.grant", auditable: @standup, metadata: ownership_metadata(ownership))

      redirect_to manager_standup_path(@standup, manager_added: "1"), status: :see_other
    end

    def destroy
      if last_manager?
        redirect_to manager_standup_path(@standup, manager_error: "At least one manager must remain."), status: :see_other
        return
      end

      metadata = ownership_metadata(@ownership)
      @ownership.destroy!
      audit_manager_change!("standup_manager.revoke", auditable: @standup, metadata: metadata)

      redirect_to manager_standup_path(@standup, manager_removed: "1"), status: :see_other
    end

    private

    def set_standup
      @standup = Standup.find(params[:standup_id])
      authorize_standup!(@standup)
    end

    def set_ownership
      @ownership = @standup.standup_ownerships.find(params[:id])
    end

    def standup_manager_params
      params.require(:standup_manager).permit(:user_id)
    end

    def selected_user
      user_id = standup_manager_params[:user_id].presence
      return unless user_id

      User.active.find_by(id: user_id)
    end

    def last_manager?
      @standup.standup_ownerships.where.not(id: @ownership.id).none?
    end

    def ownership_metadata(ownership)
      {
        standup_ownership_id: ownership.id,
        user_id: ownership.user_id,
        user_email: ownership.user.email,
        user_name: ownership.user.name,
        role: ownership.role
      }
    end
  end
end
