# Who is making an /api request: always a user. Browsers authenticate with
# their session cookie (plus a member identity after Slack or Microsoft
# sign-in); scripts send that user's access token as a bearer token.
# Authorization only looks at the user, so both behave the same way.
class Principal
  attr_reader :user, :member

  def self.from_bearer(user)
    new(user: user, bearer: true)
  end

  def self.from_session(user:, member:)
    new(user: user, member: member)
  end

  def initialize(user: nil, member: nil, bearer: false)
    @user = user
    @member = member
    @bearer = bearer
  end

  def bearer?
    @bearer
  end

  def authenticated?
    user.present? || member.present?
  end

  def admin?
    user&.admin? || false
  end

  # People who can use the management side of the console.
  def manager?
    user.present?
  end

  def can_manage?(standup)
    standup.manageable_by?(user)
  end

  def manageable_standups
    Standup.manageable_by(user)
  end

  def audit_attributes
    { actor: user }
  end

  def audit_metadata
    bearer? ? { auth_method: "access_token" } : {}
  end
end
