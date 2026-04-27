class AuditLogger
  def self.log!(actor:, action:, auditable:, metadata: {}, request: nil, actor_label: nil)
    new(
      actor: actor,
      action: action,
      auditable: auditable,
      metadata: metadata,
      request: request,
      actor_label: actor_label
    ).log!
  end

  def initialize(actor:, action:, auditable:, metadata:, request:, actor_label:)
    @actor = actor
    @action = action
    @auditable = auditable
    @metadata = metadata || {}
    @request = request
    @actor_label = actor_label
  end

  def log!
    AuditLog.create!(
      actor: actor,
      actor_email: actor&.email,
      actor_role: actor&.role,
      actor_label: actor_label || default_actor_label,
      action: action,
      auditable: auditable,
      metadata: metadata,
      request_id: request&.request_id,
      ip_address: request&.remote_ip,
      user_agent: request&.user_agent.to_s.first(255)
    )
  end

  private

  attr_reader :actor, :action, :auditable, :metadata, :request, :actor_label

  def default_actor_label
    "system" unless actor
  end
end
