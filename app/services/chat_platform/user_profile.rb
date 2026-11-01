module ChatPlatform
  UserProfile = Struct.new(
    :id, :name, :display_name, :real_name, :email, :timezone, :avatar_url,
    :deleted, :bot, :guest,
    keyword_init: true
  ) do
    def preferred_name
      display_name.presence || real_name.presence || name.presence
    end

    def deleted?
      deleted == true
    end

    def bot?
      bot == true
    end

    def guest?
      guest == true
    end
  end
end
