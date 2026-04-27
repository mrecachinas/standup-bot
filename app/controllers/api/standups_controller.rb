module Api
  class StandupsController < BaseController
    def index
      standups = Standup.order(:name)
      render json: {
        standups: standups.map { |standup| serialize_standup(standup, include_counts: true) }
      }
    end

    def show
      standup = Standup.find(params[:id])
      render json: { standup: serialize_standup(standup, include_counts: true) }
    end

    def create
      standup = Standup.new(standup_params)

      if standup.save
        StandupMetrics.track("admin.standup_created", standup_id: standup.id)
        render json: { standup: serialize_standup(standup, include_counts: true) }, status: :created
      else
        render json: { errors: standup.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      standup = Standup.find(params[:id])

      if standup.update(standup_params)
        StandupMetrics.track("admin.standup_updated", standup_id: standup.id)
        render json: { standup: serialize_standup(standup, include_counts: true) }
      else
        render json: { errors: standup.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      standup = Standup.find(params[:id])
      standup.destroy!
      StandupMetrics.track("admin.standup_deleted", standup_id: standup.id)
      head :no_content
    end

    private

    def standup_params
      params.require(:standup).permit(
        :name,
        :slack_channel,
        :intro,
        :outro,
        :schedule_type,
        :default_hour,
        :default_minute,
        :respect_timezone,
        :active,
        questions: [],
        schedule_days: []
      )
    end

    def serialize_standup(standup, include_counts: false)
      payload = {
        id: standup.id,
        name: standup.name,
        slack_channel: standup.slack_channel,
        intro: standup.intro,
        outro: standup.outro,
        questions: standup.questions || [],
        schedule_type: standup.schedule_type,
        schedule_days: standup.schedule_days || [],
        default_hour: standup.default_hour,
        default_minute: standup.default_minute,
        respect_timezone: standup.respect_timezone,
        active: standup.active,
        created_at: standup.created_at&.iso8601,
        updated_at: standup.updated_at&.iso8601
      }

      if include_counts
        payload[:participants_count] = standup.standup_participants.count
        payload[:active_participants_count] = standup.standup_participants.active.count
        payload[:responses_count] = standup.standup_responses.count
      end

      payload
    end
  end
end
