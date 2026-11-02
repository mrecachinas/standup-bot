module Api
  module Me
    # The signed-in member's time away across their standups.
    class AvailabilityController < BaseController
      MAX_AWAY_DAYS = 365

      before_action :require_member!

      def show
        render json: availability_payload
      end

      def update
        away_until = ReportingRange.parse_date(params[:away_until])
        selected = active_participants.select { |participant| selected_standup_ids.include?(participant.standup_id) }

        error = availability_error(away_until, selected)
        if error
          render json: availability_payload(selected_standup_ids: selected_standup_ids).merge(error: error, errors: [ error ]),
            status: :unprocessable_entity
          return
        end

        selected.each do |participant|
          participant.update!(vacation_until: away_until)
          audit!(participant, "standup_participant.away", vacation_until: away_until.iso8601)
        end
        render json: availability_payload.merge(notice: "You're marked away through #{away_until.to_fs(:weekday_month_day)}.")
      end

      def clear
        current_member.participants.select { |participant| participant.vacation_until.present? && participant.vacation_until >= Date.current }.each do |participant|
          # Slack's `away` command also deactivates; undo that the same way `back` does.
          participant.update!(vacation_until: nil, active: true)
          audit!(participant, "standup_participant.back")
        end
        render json: availability_payload.merge(notice: "Welcome back. You'll get your next check-ins as usual.")
      end

      private

      def availability_payload(selected_standup_ids: nil)
        MemberAvailabilitySerializer.new(current_member, max_away_days: MAX_AWAY_DAYS, selected_standup_ids: selected_standup_ids).as_json
      end

      def active_participants
        current_member.participants.select(&:active?)
      end

      def selected_standup_ids
        Array(params[:standup_ids]).map(&:to_i)
      end

      def availability_error(away_until, selected)
        return "Choose the last day you'll be away." if away_until.nil?
        return "The last day away can't be in the past." if away_until < Date.current
        return "You can only set time away up to a year ahead." if away_until > Date.current + MAX_AWAY_DAYS
        "Choose at least one standup." if selected.empty?
      end

      def audit!(participant, action, metadata = {})
        AuditLogger.log!(
          actor: current_user,
          actor_label: "#{current_member.name} (#{current_member.platform_user_id})",
          action: action,
          auditable: participant,
          metadata: metadata.merge(standup_id: participant.standup_id),
          request: request
        )
      end
    end
  end
end
