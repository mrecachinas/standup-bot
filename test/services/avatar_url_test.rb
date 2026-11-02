require "test_helper"

class AvatarUrlTest < ActiveSupport::TestCase
  test "keeps only https URLs of a sane length" do
    assert_equal "https://example.com/a.png", AvatarUrl.sanitize("https://example.com/a.png")
    assert_nil AvatarUrl.sanitize("http://example.com/a.png")
    assert_nil AvatarUrl.sanitize("javascript:alert(1)")
    assert_nil AvatarUrl.sanitize("https://example.com/#{'a' * AvatarUrl::MAX_LENGTH}")
    assert_nil AvatarUrl.sanitize(nil)
  end

  test "participants and users never store an unsafe avatar" do
    participant = standup_participants(:one)
    participant.update!(avatar_url: "javascript:alert(1)")
    assert_nil participant.reload.avatar_url

    user = users(:manager)
    user.update!(avatar_url: "https://example.com/me.png")
    assert_equal "https://example.com/me.png", user.reload.avatar_url
    user.update!(avatar_url: "http://example.com/me.png")
    assert_nil user.reload.avatar_url
  end
end
