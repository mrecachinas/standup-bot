require "openssl"

class User < ApplicationRecord
  ROLES = %w[user manager admin].freeze
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

  def user?
    role == "user"
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
