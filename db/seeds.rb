# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end

if ENV["MANAGER_ADMIN_EMAIL"].present? && ENV["MANAGER_ADMIN_TOKEN"].present?
  admin = User.find_or_initialize_by(email: ENV.fetch("MANAGER_ADMIN_EMAIL"))
  admin.assign_attributes(
    name: ENV.fetch("MANAGER_ADMIN_NAME", "Admin"),
    role: "admin",
    active: true
  )
  admin.access_token = ENV.fetch("MANAGER_ADMIN_TOKEN")
  admin.save!

  puts "Seeded manager admin #{admin.email}"
end
