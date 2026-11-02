# Responses created before standup_date existed were left NULL, which forced every
# query to fall back to created_at. Give them the date the create callback would
# have assigned, then require it.
class RequireStandupResponseDate < ActiveRecord::Migration[8.1]
  class Response < ActiveRecord::Base
    self.table_name = "standup_responses"
  end

  def up
    Response.where(standup_date: nil).find_each(order: :desc) do |response|
      date = response.created_at.in_time_zone(Time.zone).to_date
      taken = Response.where(standup_id: response.standup_id, platform_user_id: response.platform_user_id, standup_date: date).exists?

      # The unique (standup, person, date) index would reject a second response for
      # the same day; keep the one already dated (or, between two legacy rows, the newer one).
      if taken
        response.delete
      else
        response.update_columns(standup_date: date)
      end
    end

    change_column_null :standup_responses, :standup_date, false
  end

  def down
    change_column_null :standup_responses, :standup_date, true
  end
end
