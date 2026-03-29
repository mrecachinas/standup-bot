namespace :standups do
  desc "Validate standup YAML config files in config/standups"
  task validate: :environment do
    config_dir = ENV.fetch("STANDUPS_CONFIG_DIR", Rails.root.join("config", "standups"))
    yaml_files = Dir[File.join(config_dir, "*.yml")]

    if yaml_files.empty?
      puts "No standup config files found in #{config_dir}"
      exit 0
    end

    errors = []

    yaml_files.each do |file|
      basename = File.basename(file)
      file_errors = validate_standup_file(file)
      if file_errors.any?
        errors << { file: basename, errors: file_errors }
      else
        puts "✓ #{basename}"
      end
    end

    if errors.any?
      puts ""
      errors.each do |entry|
        puts "✗ #{entry[:file]}:"
        entry[:errors].each { |e| puts "  - #{e}" }
      end
      puts "\n#{errors.length} file(s) with errors"
      exit 1
    else
      puts "\nAll #{yaml_files.length} config file(s) valid"
    end
  end

  def self.validate_standup_file(file)
    valid_days = %w[sunday monday tuesday wednesday thursday friday saturday]
    required_keys = %w[name slack_channel questions]
    errors = []

    begin
      data = YAML.safe_load(File.read(file))
    rescue Psych::SyntaxError => e
      return [ "Invalid YAML: #{e.message}" ]
    end

    unless data.is_a?(Hash)
      return [ "Expected a YAML mapping, got #{data.class}" ]
    end

    # Required top-level keys
    required_keys.each do |key|
      errors << "Missing required key: '#{key}'" unless data[key].present?
    end

    # Questions must be an array of strings
    if data["questions"].is_a?(Array)
      data["questions"].each_with_index do |q, i|
        errors << "questions[#{i}] must be a string, got #{q.class}" unless q.is_a?(String)
      end
    elsif data["questions"]
      errors << "'questions' must be an array"
    end

    # Schedule validation
    if (schedule = data["schedule"])
      unless schedule.is_a?(Hash)
        errors << "'schedule' must be a mapping"
      else
        if schedule["time"]
          unless schedule["time"].match?(/\A\d{1,2}:\d{2}\z/)
            errors << "schedule.time must be HH:MM format, got '#{schedule["time"]}'"
          else
            hour, minute = schedule["time"].split(":").map(&:to_i)
            errors << "schedule.time hour must be 0-23, got #{hour}" unless (0..23).cover?(hour)
            errors << "schedule.time minute must be 0-59, got #{minute}" unless (0..59).cover?(minute)
          end
        end

        if schedule["days"]
          unless schedule["days"].is_a?(Array)
            errors << "schedule.days must be an array"
          else
            schedule["days"].each do |day|
              unless valid_days.include?(day.to_s.downcase)
                errors << "schedule.days contains invalid day: '#{day}' (valid: #{valid_days.join(', ')})"
              end
            end
          end
        end
      end
    end

    # Participants validation
    if data["participants"]
      unless data["participants"].is_a?(Array)
        errors << "'participants' must be an array"
      else
        data["participants"].each_with_index do |p, i|
          errors << "participants[#{i}] missing 'slack_id'" unless p["slack_id"].present?
          errors << "participants[#{i}] missing 'name'" unless p["name"].present?
        end
      end
    end

    errors
  end

  desc "Import or update standups from YAML files in config/standups"
  task import: :environment do
    config_dir = ENV.fetch("STANDUPS_CONFIG_DIR", Rails.root.join("config", "standups"))
    yaml_files = Dir[File.join(config_dir, "*.yml")]

    puts "Found #{yaml_files.length} standup configuration files"

    yaml_files.each do |file|
      puts "Processing #{File.basename(file)}..."
      standup_data = YAML.safe_load(File.read(file))

      # Find existing standup by name or create a new one
      standup = Standup.find_or_initialize_by(name: standup_data["name"])

      # Update basic attributes
      standup.slack_channel = standup_data["slack_channel"]
      standup.intro = standup_data["intro"]
      standup.outro = standup_data["outro"]
      standup.questions = standup_data["questions"]

      # Map schedule config to model attributes
      if (schedule = standup_data["schedule"])
        standup.respect_timezone = schedule["timezone"].present?

        if schedule["days"]
          day_names = schedule["days"].map(&:downcase)
          weekdays = %w[monday tuesday wednesday thursday friday]

          if day_names.sort == weekdays.sort
            standup.schedule_type = "weekdays"
          elsif day_names.length == 7
            standup.schedule_type = "daily"
          else
            standup.schedule_type = "weekly"
            day_map = { "sunday" => 0, "monday" => 1, "tuesday" => 2, "wednesday" => 3,
                        "thursday" => 4, "friday" => 5, "saturday" => 6 }
            standup.schedule_days = day_names.map { |d| day_map[d] }.compact
          end
        end

        if schedule["time"]
          hour, minute = schedule["time"].split(":").map(&:to_i)
          standup.default_hour = hour
          standup.default_minute = minute || 0
        end
      end

      # Save the standup
      if standup.save
        puts "- Saved standup: #{standup.name}"
      else
        puts "- Error saving standup: #{standup.errors.full_messages.join(', ')}"
        next
      end

      # Process participants
      if standup_data["participants"]
        standup_data["participants"].each do |participant_data|
          participant = StandupParticipant.find_or_initialize_by(
            standup_id: standup.id,
            slack_id: participant_data["slack_id"]
          )

          participant.slack_name = participant_data["name"]
          participant.active = participant_data.fetch("active", true)

          if participant.save
            puts "  - Added participant: #{participant.slack_name}"
          else
            puts "  - Error adding participant: #{participant.errors.full_messages.join(', ')}"
          end
        end

        # Deactivate any participants not in the YAML file
        current_slack_ids = standup_data["participants"].map { |p| p["slack_id"] }
        standup.standup_participants
          .where.not(slack_id: current_slack_ids)
          .update_all(active: false)
      end
    end

    puts "Standup import completed!"
  end
end
