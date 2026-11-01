module Manager
  # Lets someone who manages a standup share that with people in it. Ownership
  # is per standup, so this never grants access to any other standup.
  class StandupManagersController < ApplicationController
    before_action :set_standup

    def create
      participant = @standup.standup_participants.find(params[:participant_id])
      user = User.for_participant!(participant)
      unless user.active?
        redirect_to manager_standup_participants_path(@standup), alert: "#{participant.display_name}'s account is turned off, so they can't manage standups.", status: :see_other
        return
      end

      ownership = @standup.standup_ownerships.find_or_create_by!(user: user) { |record| record.role = "manager" }
      audit_manager_change!("standup.manager.add", auditable: @standup, metadata: { user_id: user.id, platform_user_id: participant.platform_user_id, ownership_id: ownership.id })
      redirect_to manager_standup_participants_path(@standup), notice: "#{participant.display_name} can now manage #{@standup.name}.", status: :see_other
    end

    def destroy
      ownership = @standup.standup_ownerships.find_by!(user_id: params[:id])
      if @standup.standup_ownerships.count <= 1
        redirect_to manager_standup_participants_path(@standup), alert: "#{@standup.name} needs at least one manager.", status: :see_other
        return
      end

      ownership.destroy!
      audit_manager_change!("standup.manager.remove", auditable: @standup, metadata: { user_id: ownership.user_id })

      if @standup.manageable_by?(current_user)
        redirect_to manager_standup_participants_path(@standup), notice: "#{ownership.user.name} no longer manages #{@standup.name}.", status: :see_other
      else
        redirect_to manager_standups_path, notice: "You no longer manage #{@standup.name}.", status: :see_other
      end
    end

    private

    def set_standup
      @standup = Standup.find(params[:standup_id])
      authorize_standup!(@standup)
    end
  end
end
