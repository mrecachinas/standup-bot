require "openssl"

class User < ApplicationRecord
  # "manager" is the standard role: anyone can create standups and manage the
  # ones they own. Admins can manage every standup and see the Admin page.
  ROLES = %w[manager admin].freeze
  SLACK_PLACEHOLDER_EMAIL_DOMAIN = "slack-users.invalid".freeze

  LinkConflict = Class.new(StandardError)
  TOKEN_DIGEST_PATTERN = /\A\h{64}\z/

  has_many :standup_ownerships, dependent: :destroy
  has_many :owned_standups, through: :standup_ownerships, source: :standup
  has_many :audit_logs, foreign_key: :actor_id, dependent: :nullify

  before_validation :normalize_email

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }
  validates :access_token_digest, presence: true, format: { with: TOKEN_DIGEST_PATTERN }

  scope :active, -> { where(active: true) }
  scope :admins, -> { where(role: "admin") }
  scope :managers, -> { where(role: "manager") }

  def self.authenticate(email, access_token)
    user = active.find_by(email: normalize_email(email))
    return unless user&.authenticate_access_token(access_token)

    user
  end

  # Find or create the account for someone who signed in with Slack.
  def self.from_slack_identity(identity)
    find_by(slack_user_id: identity.slack_id) ||
      link_slack_identity_by_email(identity) ||
      create_from_slack_identity!(identity)
  end

  def self.link_slack_identity_by_email(identity)
    return unless identity.email_verified && identity.email.present?

    user = find_by(email: normalize_email(identity.email))
    return unless user
    raise LinkConflict, "That email is already linked to a different Slack account." if user.slack_user_id.present?

    user.update!(slack_user_id: identity.slack_id)
    user
  end

  def self.create_from_slack_identity!(identity)
    email = normalize_email(identity.email)
    if !identity.email_verified || email.blank? || exists?(email: email)
      email = "#{identity.slack_id.downcase}@#{SLACK_PLACEHOLDER_EMAIL_DOMAIN}"
    end

    create!(
      name: identity.name.presence || identity.slack_id,
      email: email,
      role: "manager",
      slack_user_id: identity.slack_id,
      avatar_url: (identity.avatar_url if SlackAvatar.safe_url?(identity.avatar_url)),
      access_token: SecureRandom.hex(32)
    )
  end

  # The account for someone in a standup, created if they've never signed in.
  # They'll be matched by Slack user ID when they sign in with Slack later.
  def self.for_participant!(participant)
    find_by(slack_user_id: participant.slack_id) ||
      create_from_slack_identity!(
        SlackSignIn::Identity.new(slack_id: participant.slack_id, name: participant.slack_name, email: nil, email_verified: false, avatar_url: participant.avatar_url)
      )
  end

  def self.digest_access_token(access_token)
    OpenSSL::Digest::SHA256.hexdigest(access_token.to_s)
  end

  def self.normalize_email(email)
    email.to_s.strip.downcase
  end

  def access_token=(access_token)
    self.access_token_digest = self.class.digest_access_token(access_token)
  end

  def authenticate_access_token(access_token)
    return false if access_token.blank? || access_token_digest.blank?

    digest = self.class.digest_access_token(access_token)
    ActiveSupport::SecurityUtils.secure_compare(access_token_digest, digest)
  end

  def admin?
    role == "admin"
  end

  def manager?
    role == "manager"
  end

  def can_manage_standup?(standup)
    return false unless active? && standup.present?

    admin? || standup_ownerships.exists?(standup_id: standup.id)
  end

  def manageable_standups
    Standup.manageable_by(self)
  end

  private

  def normalize_email
    self.email = self.class.normalize_email(email)
  end
end
