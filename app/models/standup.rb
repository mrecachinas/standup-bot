require "json"

class Standup < ApplicationRecord
  has_many :standup_participants, dependent: :destroy
  has_many :standup_responses, dependent: :destroy

  attribute :intro, :text, default: "Good morning! Time for standup. When you're ready, please answer the following"
  attribute :outro, :text, default: "Thanks for your answers! Have a great day!"
  attribute :questions, :json, default: -> { [] }
  attribute :schedule_days, :json, default: -> { [] }

  validates :name, presence: true
  validates :slack_channel, presence: true
  validates :questions, presence: true
  validates :schedule_type, inclusion: { in: %w[daily weekdays weekly] }
  validates :respect_timezone, inclusion: { in: [ true, false ] }

  # For custom schedules, store as array of weekday numbers (0=Sunday, 6=Saturday)
  # For weekly, store day of week (0-6)
  # For biweekly/monthly, store day of month (1-31)

  scope :active, -> { where(active: true) }

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

      # In Ruby/Rails, wday is: 0=Sunday, 1=Monday, ..., 6=Saturday
      # But beginning_of_week starts with Monday, so we need to adjust
      next_time = if day_of_week == 0  # Sunday
        now.beginning_of_week - 1.day  # Sunday is 1 day before beginning of week (Monday)
      else
        now.beginning_of_week + (day_of_week - 1).days  # Adjust for Monday=1 offset
      end

      next_time = next_time.change(hour: default_hour, min: default_minute)

      # If this week's occurrence has passed, go to next week
      next_time += 1.week if next_time < now

      next_time

    else
      raise ArgumentError, "Unsupported schedule_type: #{schedule_type}"
    end
  end

  private

  # Advances the given time to the next weekday (Monday-Friday)
  def advance_to_next_weekday(time)
    new_time = time.dup

    # Add days until we reach a weekday
    loop do
      new_time += 1.day
      # Check if it's a weekday (Monday = 1, Friday = 5)
      break if (1..5).include?(new_time.wday)
    end

    # Set the time to the configured hour and minute
    new_time.change(hour: default_hour, min: default_minute)
  end
end
