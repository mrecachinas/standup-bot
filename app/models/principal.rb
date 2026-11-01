# Who is making an /api request. It's either the admin API token (scripts and
# internal tools) or someone signed in to the console through their session
# cookie. Authorization checks ask the principal rather than branching on how
# the request authenticated.
class Principal
  attr_reader :user, :member

  def self.admin_token
    new(token: true)
  end

  def self.from_session(user:, member:)
    new(user: user, member: member)
  end

  def initialize(user: nil, member: nil, token: false)
    @user = user
    @member = member
    @token = token
  end

  def token?
    @token
  end

  def authenticated?
    token? || user.present? || member.present?
  end

  def admin?
    token? || user&.admin? || false
  end

  # People who can use the management side of the console (or the token).
  def manager?
    token? || user.present?
  end

  def can_manage?(standup)
    token? || standup.manageable_by?(user)
  end

  def manageable_standups
    token? ? Standup.all : Standup.manageable_by(user)
  end

  def audit_attributes
    return { actor: nil, actor_label: "admin_api" } if token?

    { actor: user }
  end

  def audit_metadata
    token? ? { auth_method: "admin_api_token" } : {}
  end
end
