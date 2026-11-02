module Api
  # Admin API: index/create/destroy with `participant: {...}`. The console adds
  # `?view=console` on index, `lookup: true` on create (resolve a handle, name,
  # or email through the chat platform), update, bulk_import, and sync.
  class StandupParticipantsController < BaseController
    before_action :require_manager!
    before_action :set_standup
    before_action :set_participant, only: [ :update, :destroy ]

    def index
      participants = @standup.standup_participants.order(:display_name, :platform_user_id).to_a

      if params[:view] == "console"
        render json: console_payload(participants)
      else
        render json: {
          participants: participants.map { |participant| serialize_participant(participant) }
        }
      end
    end

    def create
      participant = @standup.standup_participants.new(lookup_requested? ? resolved_participant_params : participant_params)

      if participant.save
        StandupMetrics.track("admin.participant_created", standup_id: @standup.id, participant_id: participant.id)
        audit_change!(
          "standup_participant.create",
          auditable: participant,
          metadata: { standup_id: @standup.id, attributes: audited_participant_attributes(participant) }
        )
        render json: {
          participant: serialize_participant(participant),
          notice: "Added #{participant.display_name} to #{@standup.name}."
        }, status: :created
      else
        render_validation_errors(participant.errors)
      end
    rescue ChatUserResolver::ResolutionError => error
      participant = @standup.standup_participants.new(participant_params)
      participant.errors.add(:base, error.message)
      render_validation_errors(participant.errors)
    end

    def update
      if @participant.update(participant_params)
        audit_change!(
          "standup_participant.update",
          auditable: @participant,
          metadata: { standup_id: @standup.id, changes: audited_changes(@participant) }
        )
        render json: {
          participant: serialize_participant(@participant),
          notice: "Saved #{@participant.display_name}."
        }
      else
        render_validation_errors(@participant.errors)
      end
    end

    def destroy
      metadata = {
        standup_id: @standup.id,
        platform_user_id: @participant.platform_user_id,
        display_name: @participant.display_name,
        attributes: audited_participant_attributes(@participant)
      }
      @participant.destroy!
      StandupMetrics.track("admin.participant_deleted", standup_id: @standup.id, participant_id: @participant.id)
      audit_change!("standup_participant.destroy", auditable: @participant, metadata: metadata)
      head :no_content
    end

    def bulk_import
      result = StandupParticipantImporter.new(@standup, user_resolver: ChatUserResolver.for(@standup.platform)).import_text(params[:participants_text])
      render_import_result(result, "standup_participant.bulk_import", "bulk_import", notice: import_notice("Import finished", result))
    end

    def sync
      channel = params[:channel].presence || @standup.platform_channel
      deactivate_missing = ActiveModel::Type::Boolean.new.cast(params[:deactivate_missing]) || false
      unless principal.admin? || channel_member?(channel)
        render json: { errors: [ "You can only sync people from a channel you're in." ], summary: nil }, status: :unprocessable_entity
        return
      end

      profiles = ChatPlatform.for_standup(@standup).channel_member_profiles(channel)
      result = StandupParticipantImporter.new(@standup).sync_profiles(profiles, deactivate_missing: deactivate_missing)
      render_import_result(
        result,
        "standup_participant.sync",
        "#{@standup.platform}_sync",
        notice: import_notice("Synced #{@standup.chat_platform.label} channel", result)
      )
    rescue StandardError => error
      label = @standup.chat_platform.label
      Rails.logger.warn "Unable to sync #{label} channel #{channel}: #{error.class} - #{error.message}"
      render json: {
        errors: [ "Unable to sync #{label} channel. Check the channel and #{label} app permissions, then try again." ],
        summary: nil
      }, status: :unprocessable_entity
    end

    private

    def set_participant
      @participant = @standup.standup_participants.find(params[:id])
    end

    def console_payload(participants)
      today = Date.current
      holiday_today = @standup.holiday_on?(today)
      managers = @standup.standup_ownerships.includes(user: :identities).map(&:user).sort_by { |user| user.name.downcase }
      manager_ids_by_platform_user_id = managers.filter_map do |user|
        user_id = user.platform_user_id_for(@standup.platform)
        [ user_id, user.id ] if user_id.present?
      end.to_h

      {
        participants: participants.map do |participant|
          ParticipantRosterSerializer.new(
            participant,
            manager_user_id: manager_ids_by_platform_user_id[participant.platform_user_id],
            manager_count: managers.size,
            holiday_today: holiday_today,
            today: today
          ).as_json
        end,
        standup: StandupSerializer.new(@standup, include_counts: true).as_json,
        platform: PlatformSerializer.new(@standup.platform).as_json,
        managers: managers.map do |user|
          ParticipantManagerSerializer.new(user, standup: @standup, manager_count: managers.size, current_user: current_user).as_json
        end,
        manager_rules: {
          minimum_managers: 1,
          can_remove_managers: managers.size > 1,
          only_admins_manage: managers.empty?
        },
        summary: {
          participant_count: participants.size,
          active_count: participants.count(&:active?),
          stale_timezone_count: participants.count { |participant| participant.timezone_cache_status != "fresh" },
          holiday_today: holiday_today
        },
        sync_defaults: {
          channel: @standup.platform_channel,
          channel_name: @standup.platform_channel_name,
          deactivate_missing: false
        }
      }
    end

    # Non-admins can only pull in members of channels they belong to, so the
    # bot can't be used to list the members of someone else's private channel.
    def channel_member?(channel)
      user_id = current_user&.platform_user_id_for(@standup.platform)
      user_id.present? && ChatPlatform.for_standup(@standup).channel_member_ids(channel).include?(user_id)
    end

    def lookup_requested?
      ActiveModel::Type::Boolean.new.cast(params[:lookup])
    end

    def participant_params
      permitted = params.require(:participant).permit(
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

      resolved_user = ChatUserResolver.for(@standup.platform).resolve(identifier, fallback_name: permitted[:display_name])
      attributes = resolved_user.fill_in(permitted.to_h.symbolize_keys)
      attributes.delete(:avatar_url) unless SlackAvatar.safe_url?(attributes[:avatar_url])
      attributes
    end

    def render_import_result(result, summary_action, source, notice:)
      audit_import_result!(result, summary_action, source) if result.success? || result.changed_count.positive?

      if result.success?
        render json: { notice: notice, summary: result.summary, errors: [] }
      else
        render json: { errors: result.errors, summary: result.summary }, status: :unprocessable_entity
      end
    end

    def import_notice(prefix, result)
      summary = result.summary
      parts = [
        "#{summary[:created_count]} added",
        "#{summary[:updated_count]} updated",
        "#{summary[:unchanged_count]} unchanged"
      ]
      parts << "#{summary[:deactivated_count]} marked inactive" if summary[:deactivated_count].positive?
      "#{prefix}: #{parts.join(', ')}."
    end

    def audit_import_result!(result, summary_action, source)
      result.changes.each do |change|
        audit_change!(change.action, auditable: change.participant, metadata: change.metadata.merge(source: source))
      end

      return unless result.changed_count.positive?

      audit_change!(summary_action, auditable: @standup, metadata: result.summary.merge(source: source))
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

    def serialize_participant(participant)
      ParticipantSerializer.new(participant).as_json
    end
  end
end
