require "test_helper"

class UiHelperTest < ActionView::TestCase
  test "avatars show the Slack photo over the initials" do
    html = avatar("Ada Lovelace", url: "https://avatars.slack-edge.com/ada.png")

    assert_includes html, "AL"
    assert_includes html, %(src="https://avatars.slack-edge.com/ada.png")
    assert_includes html, %(class="avatar-img")
  end

  test "avatars fall back to initials without a safe URL" do
    html = avatar("Ada Lovelace", url: "javascript:alert(1)")

    assert_includes html, "AL"
    assert_not_includes html, "<img"
  end

  test "avatar stacks accept name and photo pairs" do
    html = avatar_stack([ [ "Ada Lovelace", "https://avatars.slack-edge.com/ada.png" ], [ "Alan Turing", nil ] ])

    assert_equal 1, html.scan("<img").size
    assert_includes html, "AT"
  end
end
