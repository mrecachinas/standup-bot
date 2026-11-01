module Me
  class AvailabilityController < ApplicationController
    MAX_AWAY_DAYS = 365

    def show
      @participants = active_participants
    end

    def update
      away_until = parse_date(params[:away_until])
      selected = active_participants.select { |participant| selected_standup_ids.include?(participant.standup_id) }

      error = availability_error(away_until, selected)
      if error
        @participants = active_participants
        @error = error
        render :show, status: :unprocessable_entity
        return
      end

      selected.each do |participant|
        participant.update!(vacation_until: away_until)
        audit!(participant, "standup_participant.away", vacation_until: away_until.iso8601)
      end
      redirect_to me_availability_path, notice: "You're marked away through #{away_until.strftime("%A, %B %-d")}.", status: :see_other
    end

    def clear
      current_member.participants.select { |participant| participant.vacation_until.present? && participant.vacation_until >= Date.current }.each do |participant|
        # Slack's `away` command also deactivates; undo that the same way `back` does.
        participant.update!(vacation_until: nil, active: true)
        audit!(participant, "standup_participant.back")
      end
      redirect_to me_availability_path, notice: "Welcome back. You'll get your next check-ins as usual.", status: :see_other
    end

    private

    def active_participants
      current_member.participants.select(&:active?)
    end

    def selected_standup_ids
      Array(params[:standup_ids]).map(&:to_i)
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      nil
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
        actor_label: "#{current_member.name} (#{current_member.slack_id})",
        action: action,
        auditable: participant,
        metadata: metadata.merge(standup_id: participant.standup_id),
        request: request
      )
    end
  end
end
