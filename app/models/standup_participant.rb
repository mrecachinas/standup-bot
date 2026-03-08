class StandupParticipant < ApplicationRecord
  belongs_to :standup

  validates :slack_id, presence: true
  validates :slack_id, uniqueness: { scope: :standup_id }

  # Fetch participant info from Slack as needed
  def fetch_info
    SlackClient.instance.get_user_info(slack_id)
  end

  # Get participant's timezone, using cached value when available
  def timezone
    return cached_timezone if cached_timezone.present?

    info = fetch_info
    tz = info&.dig("tz") || "UTC"

    # Cache for future use
    update_column(:cached_timezone, tz) if persisted?

    tz
  end

  # Calculate send time based on standup settings and user's timezone
  def calculate_send_time
    if standup.respect_timezone
      # Use participant's timezone with nil-safe fallback
      tz = ActiveSupport::TimeZone[timezone] || ActiveSupport::TimeZone["UTC"]

      # Get the next occurrence based on standup's schedule in user's timezone
      next_occurrence = standup.next_occurrence_in_timezone(tz)

      # Return the UTC time
      next_occurrence.in_time_zone("UTC")
    else
      # Use UTC directly - everyone gets it at the same UTC time
      utc_tz = ActiveSupport::TimeZone["UTC"]
      standup.next_occurrence_in_timezone(utc_tz)
    end
  end
end
