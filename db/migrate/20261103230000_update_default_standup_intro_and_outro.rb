# The first DM now opens with a greeting that names the standup and its
# channel, so the old default intro would repeat it. Move standups still on the
# old defaults to the new ones; customized text is left alone.
class UpdateDefaultStandupIntroAndOutro < ActiveRecord::Migration[8.1]
  OLD_INTRO = "Good morning! Time for standup. When you're ready, please answer the following".freeze
  NEW_INTRO = "Please share what you've been working on.".freeze
  OLD_OUTRO = "Thanks for your answers! Have a great day!".freeze
  NEW_OUTRO = "Thanks for sharing! Have a great day. 🙌".freeze

  class MigrationStandup < ActiveRecord::Base
    self.table_name = "standups"
  end

  def up
    MigrationStandup.where(intro: OLD_INTRO).update_all(intro: NEW_INTRO)
    MigrationStandup.where(outro: OLD_OUTRO).update_all(outro: NEW_OUTRO)
  end

  def down
    MigrationStandup.where(intro: NEW_INTRO).update_all(intro: OLD_INTRO)
    MigrationStandup.where(outro: NEW_OUTRO).update_all(outro: OLD_OUTRO)
  end
end
