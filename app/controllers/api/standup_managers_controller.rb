module Api
  # Lets someone who manages a standup share that with people in it. Ownership
  # is per standup, so this never grants access to any other standup.
  class StandupManagersController < BaseController
    before_action :require_manager!
    before_action :set_standup

    def create
      participant = @standup.standup_participants.find(params.require(:participant_id))
      user = User.for_participant!(participant)
      unless user.active?
        render json: { errors: [ "#{participant.display_name}'s account is turned off, so they can't manage standups." ] }, status: :unprocessable_entity
        return
      end

      ownership = @standup.standup_ownerships.find_or_create_by!(user: user) { |record| record.role = "manager" }
      audit_change!("standup.manager.add", auditable: @standup, metadata: { user_id: user.id, platform_user_id: participant.platform_user_id, ownership_id: ownership.id })
      render json: {
        manager: serialize_manager(user),
        participant_id: participant.id,
        can_manage: true,
        notice: "#{participant.display_name} can now manage #{@standup.name}."
      }, status: ownership.previously_new_record? ? :created : :ok
    end

    def destroy
      ownership = @standup.standup_ownerships.find_by!(user_id: params[:id])
      if @standup.standup_ownerships.count <= 1
        render json: { errors: [ "#{@standup.name} needs at least one manager." ] }, status: :unprocessable_entity
        return
      end

      ownership.destroy!
      audit_change!("standup.manager.remove", auditable: @standup, metadata: { user_id: ownership.user_id })

      if principal.can_manage?(@standup)
        render json: { can_manage: true, user_id: ownership.user_id, notice: "#{ownership.user.name} no longer manages #{@standup.name}." }
      else
        render json: { can_manage: false, user_id: ownership.user_id, notice: "You no longer manage #{@standup.name}." }
      end
    end

    private

    def serialize_manager(user)
      ParticipantManagerSerializer.new(
        user,
        standup: @standup,
        manager_count: @standup.standup_ownerships.count,
        current_user: current_user
      ).as_json
    end
  end
end
