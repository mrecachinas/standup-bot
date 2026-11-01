require "test_helper"

class SlackAvatarTest < ActiveSupport::TestCase
  test "picks the small https photo from a Slack profile" do
    profile = { "image_192" => "https://avatars.slack-edge.com/big.png", "image_72" => "https://avatars.slack-edge.com/small.png" }

    assert_equal "https://avatars.slack-edge.com/small.png", SlackAvatar.url_from(profile)
  end

  test "skips unsafe URLs and falls back to the next safe size" do
    safe = "https://avatars.slack-edge.com/48.png"

    assert_equal safe, SlackAvatar.url_from({ "image_72" => "javascript:alert(1)", "image_48" => safe })
    assert_equal safe, SlackAvatar.url_from({ "image_72" => "http://example.com/a.png", "image_48" => safe })
    assert_nil SlackAvatar.url_from(nil)
  end
end
