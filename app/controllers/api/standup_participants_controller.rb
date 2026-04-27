module Api
  class StandupParticipantsController < BaseController
    before_action :set_standup

    def index
      participants = @standup.standup_participants.order(:slack_name, :slack_id)
      render json: {
        participants: participants.map { |participant| serialize_participant(participant) }
      }
    end

    def create
      participant = @standup.standup_participants.new(participant_params)

      if participant.save
        StandupMetrics.track("admin.participant_created", standup_id: @standup.id, participant_id: participant.id)
        render json: { participant: serialize_participant(participant) }, status: :created
      else
        render json: { errors: participant.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      participant = @standup.standup_participants.find(params[:id])
      participant.destroy!
      StandupMetrics.track("admin.participant_deleted", standup_id: @standup.id, participant_id: participant.id)
      head :no_content
    end

    private

    def set_standup
      @standup = Standup.find(params[:standup_id])
    end

    def participant_params
      params.require(:participant).permit(:slack_id, :slack_name, :active, :cached_timezone)
    end

    def serialize_participant(participant)
      {
        id: participant.id,
        standup_id: participant.standup_id,
        slack_id: participant.slack_id,
        slack_name: participant.slack_name,
        active: participant.active,
        cached_timezone: participant.cached_timezone,
        created_at: participant.created_at&.iso8601,
        updated_at: participant.updated_at&.iso8601
      }
    end
  end
end
