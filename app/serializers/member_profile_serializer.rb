# The signed-in member: who they are and which chat app they answer in.
class MemberProfileSerializer
  def initialize(member)
    @member = member
  end

  def as_json(*)
    avatar_url = @member.avatar_url
    {
      platform: @member.platform,
      platform_label: ChatPlatform.for(@member.platform).label,
      platform_user_id: @member.platform_user_id,
      name: @member.name,
      avatar_url: avatar_url
    }
  end
end
