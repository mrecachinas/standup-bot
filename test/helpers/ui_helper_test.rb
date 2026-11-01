require "test_helper"

class UiHelperTest < ActionView::TestCase
  test "avatars show the Slack photo over the initials" do
    html = avatar("Ada Lovelace", url: "https://avatars.slack-edge.com/ada.png")

    assert_includes html, "AL"
    assert_includes html, %(src="https://avatars.slack-edge.com/ada.png")
  end

  test "avatars fall back to initials without a safe https URL" do
    [ "javascript:alert(1)", "http://example.com/a.png", nil ].each do |url|
      html = avatar("Ada Lovelace", url: url)

      assert_includes html, "AL"
      assert_not_includes html, "<img", "expected #{url.inspect} not to render as an image"
    end
  end

  test "avatar stacks accept name and photo pairs" do
    html = avatar_stack([ [ "Ada Lovelace", "https://avatars.slack-edge.com/ada.png" ], [ "Alan Turing", nil ] ])

    assert_includes html, %(src="https://avatars.slack-edge.com/ada.png")
    assert_includes html, "AT"
  end
end
