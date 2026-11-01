# A cached direct conversation between the bot and a person, for platforms
# that need one before the bot can send a DM (Teams).
class ChatConversation < ApplicationRecord
  validates :platform, :platform_user_id, :conversation_id, presence: true
  validates :platform_user_id, uniqueness: { scope: :platform }

  scope :on_platform, ->(platform) { where(platform: platform.to_s) }

  def self.remember!(platform:, platform_user_id:, conversation_id:, service_url: nil, tenant_id: nil)
    conversation = find_or_initialize_by(platform: platform.to_s, platform_user_id: platform_user_id)
    conversation.assign_attributes(
      conversation_id: conversation_id,
      service_url: service_url.presence || conversation.service_url,
      tenant_id: tenant_id.presence || conversation.tenant_id
    )
    conversation.save! if conversation.changed?
    conversation
  rescue ActiveRecord::RecordNotUnique
    retry
  end
end
