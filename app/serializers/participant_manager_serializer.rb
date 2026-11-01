# A standup's managers, as the console's People page lists them.
class ParticipantManagerSerializer
  def initialize(user, standup:, manager_count:, current_user: nil)
    @user = user
    @standup = standup
    @manager_count = manager_count
    @current_user = current_user
  end

  def as_json(*)
    {
      id: @user.id,
      name: @user.name,
      avatar_url: (@user.avatar_url if SlackAvatar.safe_url?(@user.avatar_url)),
      admin: @user.admin?,
      role_label: @user.admin? ? "Admin" : "Manager",
      platform_user_id: @user.platform_user_id_for(@standup.platform),
      current_user: @current_user.present? && @user == @current_user,
      can_remove: @manager_count > 1
    }
  end
end
