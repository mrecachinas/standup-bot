module Manager
  class StandupParticipantsController < ApplicationController
    before_action :set_standup
    before_action :set_participant, only: [ :update, :destroy ]

    def index
      prepare_index
    end

    def create
      @participant = @standup.standup_participants.new(resolved_participant_params)

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
    rescue SlackUserResolver::ResolutionError => error
      @participant = @standup.standup_participants.new(participant_params)
      @participant.errors.add(:base, error.message)
      prepare_index
      render :index, status: :unprocessable_entity
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
      result = StandupParticipantImporter.new(@standup, user_resolver: slack_user_resolver).import_text(@bulk_import_text)

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
      @sync_channel = params[:channel].presence || @standup.platform_channel
      @deactivate_missing = ActiveModel::Type::Boolean.new.cast(params[:deactivate_missing])
      unless current_user.admin? || channel_member?(@sync_channel)
        @sync_errors = [ "You can only sync people from a channel you're in." ]
        prepare_index
        render :index, status: :unprocessable_entity
        return
      end

      profiles = ChatPlatform.for_standup(@standup).channel_member_profiles(@sync_channel)
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

    # Non-admins can only pull in members of channels they belong to, so the
    # bot can't be used to list the members of someone else's private channel.
    def channel_member?(channel)
      user_id = current_user.platform_user_id_for(@standup.platform)
      user_id.present? && ChatPlatform.for_standup(@standup).channel_member_ids(channel).include?(user_id)
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
      @sync_channel ||= @standup.platform_channel
      @deactivate_missing = false if @deactivate_missing.nil?
      @participants = @standup.standup_participants.order(:display_name, :platform_user_id).to_a
      @managers = @standup.standup_ownerships.includes(:user).map(&:user).sort_by { |user| user.name.downcase }
      @manager_ids_by_platform_user_id = @managers.filter_map do |user|
        user_id = user.platform_user_id_for(@standup.platform)
        [ user_id, user.id ] if user_id.present?
      end.to_h
      replace_invalid_participant
    end

    def replace_invalid_participant
      return unless @participant&.persisted? && @participant.errors.any?

      index = @participants.index { |participant| participant.id == @participant.id }
      @participants[index] = @participant if index
    end

    def participant_params
      permitted = params.require(:standup_participant).permit(
        :platform_user_id,
        :display_name,
        :active,
        :cached_timezone,
        :vacation_until
      )
      permitted[:cached_timezone] = nil if permitted.key?(:cached_timezone) && permitted[:cached_timezone].blank?
      permitted[:vacation_until] = nil if permitted.key?(:vacation_until) && permitted[:vacation_until].blank?
      permitted
    end

    def resolved_participant_params
      permitted = participant_params
      identifier = permitted[:platform_user_id].to_s.strip
      return permitted if identifier.blank?

      resolved_user = slack_user_resolver.resolve(identifier, fallback_name: permitted[:display_name])
      permitted[:platform_user_id] = resolved_user.platform_user_id
      permitted[:display_name] = permitted[:display_name].presence || resolved_user.display_name
      permitted[:cached_timezone] = permitted[:cached_timezone].presence || resolved_user.cached_timezone
      permitted[:avatar_url] = resolved_user.avatar_url if SlackAvatar.safe_url?(resolved_user.avatar_url)
      permitted
    end

    def slack_user_resolver
      @slack_user_resolver ||= SlackUserResolver.new
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
        "platform_user_id",
        "display_name",
        "active",
        "cached_timezone",
        "cached_timezone_updated_at",
        "vacation_until"
      )
    end
  end
end
