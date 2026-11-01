# Links a console account to a person on a chat platform (Slack user ID,
# Teams/Entra object ID). One identity per platform per user.
class UserIdentity < ApplicationRecord
  belongs_to :user

  validates :platform, presence: true
  validate :platform_must_be_supported
  validates :platform_user_id, presence: true, uniqueness: { scope: :platform }
  validates :user_id, uniqueness: { scope: :platform }

  scope :on_platform, ->(platform) { where(platform: platform.to_s) }

  private

  def platform_must_be_supported
    errors.add(:platform, "isn't a supported chat platform") if platform.present? && !ChatPlatform.supported?(platform)
  end
end
