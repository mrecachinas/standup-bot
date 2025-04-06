namespace :standups do
  desc "Import or update standups from YAML files in config/standups"
  task import: :environment do
    yaml_files = Dir[Rails.root.join("config", "standups", "*.yml")]

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

      # Update schedule
      schedule = standup_data["schedule"]
      standup.timezone = schedule["timezone"]
      standup.days = schedule["days"]
      standup.time = schedule["time"]

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

          participant.name = participant_data["name"]
          participant.active = participant_data["active"]

          if participant.save
            puts "  - Added participant: #{participant.name}"
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
