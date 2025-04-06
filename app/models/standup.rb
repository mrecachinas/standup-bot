class Standup < ApplicationRecord
  has_many :standup_participants, dependent: :destroy
  has_many :standup_responses, dependent: :destroy

  validates :name, presence: true
  validates :slack_channel, presence: true
  validates :questions, presence: true
  validates :schedule_type, inclusion: { in: %w[daily weekdays weekly biweekly monthly custom] }
  validates :respect_timezone, inclusion: { in: [ true, false ] }

  # Store questions as an array in JSON
  serialize :questions, Array

  # For custom schedules, store as array of weekday numbers (0=Sunday, 6=Saturday)
  # For weekly, store day of week (0-6)
  # For biweekly/monthly, store day of month (1-31)
  serialize :schedule_days, Array

  # Default scope to only show active standups
  default_scope { where(active: true) }

  # Calculate the next occurrence of this standup in the given timezone
  def next_occurrence_in_timezone(timezone)
    now = timezone.now

    case schedule_type
    when "daily"
      # Simply today at the configured time, or tomorrow if already passed
      next_time = now.change(hour: default_hour, min: default_minute)
      next_time += 1.day if next_time < now
      next_time

    when "weekdays"
      # Next weekday (Mon-Fri) at the configured time
      next_time = now.change(hour: default_hour, min: default_minute)

      # If today is a weekend or time already passed, find next weekday
      if now.saturday? || now.sunday? || next_time < now
        next_time = advance_to_next_weekday(next_time)
      end

      next_time

    when "weekly"
      # The configured day of week at the configured time
      day_of_week = schedule_days.first || 1 # Default to Monday (1)
      next_time = now.beginning_of_week + day_of_week.days
      next_time = next_time.change(hour: default_hour, min: default_minute)

      # If this week's occurrence has passed, go to next week
      next_time += 1.week if next_time < now

      next_time

    when "biweekly"
      # Every other week on the configured day
    end
  end
end
