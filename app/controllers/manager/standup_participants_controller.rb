module Manager
  class StandupParticipantsController < ApplicationController
    before_action :set_standup
    before_action :set_participant, only: [ :update, :destroy ]

    def index
      prepare_index
    end

    def create
      @participant = @standup.standup_participants.new(participant_params)

      if @participant.save
        audit_manager_change!(
          "standup_participant.create",
          auditable: @participant,
          metadata: { standup_id: @standup.id, attributes: audited_participant_attributes(@participant) }
        )
        redirect_to manager_standup_participants_path(@standup), status: :see_other
      else
        prepare_index
        render :index, status: :unprocessable_entity
      end
    end

    def update
      if @participant.update(participant_params)
        audit_manager_change!(
          "standup_participant.update",
          auditable: @participant,
          metadata: { standup_id: @standup.id, changes: audited_changes(@participant) }
        )
        redirect_to manager_standup_participants_path(@standup), status: :see_other
      else
        prepare_index
        render :index, status: :unprocessable_entity
      end
    end

    def destroy
      snapshot = audited_participant_attributes(@participant)
      @participant.destroy!
      audit_manager_change!(
        "standup_participant.destroy",
        auditable: @participant,
        metadata: { standup_id: @standup.id, attributes: snapshot }
      )
      redirect_to manager_standup_participants_path(@standup), status: :see_other
    end

    def bulk_import
      @bulk_import_text = params[:participants_text]
      result = StandupParticipantImporter.new(@standup).import_text(@bulk_import_text)

      if result.success?
        audit_import_result!(result, "standup_participant.bulk_import", "bulk_import")
        redirect_to manager_standup_participants_path(@standup), status: :see_other
      else
        audit_import_result!(result, "standup_participant.bulk_import", "bulk_import") if result.changed_count.positive?
        @bulk_import_errors = result.errors
        prepare_index
        render :index, status: :unprocessable_entity
      end
    end

    def sync
      @sync_channel = params[:channel].presence || @standup.slack_channel
      @deactivate_missing = ActiveModel::Type::Boolean.new.cast(params[:deactivate_missing])
      profiles = SlackClient.instance.channel_member_profiles(@sync_channel)
      result = StandupParticipantImporter.new(@standup).sync_profiles(profiles, deactivate_missing: @deactivate_missing)

      if result.success?
        audit_import_result!(result, "standup_participant.sync", "slack_sync")
        redirect_to manager_standup_participants_path(@standup), status: :see_other
      else
        audit_import_result!(result, "standup_participant.sync", "slack_sync") if result.changed_count.positive?
        @sync_errors = result.errors
        prepare_index
        render :index, status: :unprocessable_entity
      end
    rescue StandardError => error
      Rails.logger.warn "Unable to sync Slack channel #{@sync_channel}: #{error.class} - #{error.message}"
      @sync_errors = [ "Unable to sync Slack channel. Check the channel and Slack app permissions, then try again." ]
      prepare_index
      render :index, status: :unprocessable_entity
    end

    private

    def set_standup
      @standup = Standup.find(params[:standup_id])
      authorize_standup!(@standup)
    end

    def set_participant
      @participant = @standup.standup_participants.find(params[:id])
    end

    def prepare_index
      @new_participant = if @participant&.new_record? && @participant.errors.any?
        @participant
      else
        @standup.standup_participants.new(active: true)
      end
      @bulk_import_text ||= nil
      @sync_channel ||= @standup.slack_channel
      @deactivate_missing = false if @deactivate_missing.nil?
      @participants = @standup.standup_participants.order(:slack_name, :slack_id).to_a
      replace_invalid_participant
    end

    def replace_invalid_participant
      return unless @participant&.persisted? && @participant.errors.any?

      index = @participants.index { |participant| participant.id == @participant.id }
      @participants[index] = @participant if index
    end

    def participant_params
      permitted = params.require(:standup_participant).permit(
        :slack_id,
        :slack_name,
        :active,
        :cached_timezone,
        :vacation_until
      )
      permitted[:cached_timezone] = nil if permitted.key?(:cached_timezone) && permitted[:cached_timezone].blank?
      permitted[:vacation_until] = nil if permitted.key?(:vacation_until) && permitted[:vacation_until].blank?
      permitted
    end

    def audit_import_result!(result, summary_action, source)
      result.changes.each do |change|
        audit_manager_change!(
          change.action,
          auditable: change.participant,
          metadata: change.metadata.merge(source: source)
        )
      end

      return unless result.changed_count.positive?

      audit_manager_change!(
        summary_action,
        auditable: @standup,
        metadata: result.summary.merge(source: source)
      )
    end

    def audited_changes(participant)
      participant.saved_changes.except("updated_at").transform_values { |before, after| [ before, after ] }
    end

    def audited_participant_attributes(participant)
      participant.attributes.slice(
        "id",
        "standup_id",
        "slack_id",
        "slack_name",
        "active",
        "cached_timezone",
        "cached_timezone_updated_at",
        "vacation_until"
      )
    end
  end
end
