# Profile photos end up in <img src>, so only https URLs of a sane length are
# kept. StandupParticipant and User apply this whenever avatar_url is assigned.
module AvatarUrl
  MAX_LENGTH = 1024

  module_function

  def safe?(url)
    url.is_a?(String) && url.start_with?("https://") && url.length <= MAX_LENGTH
  end

  def sanitize(url)
    url if safe?(url)
  end
end
