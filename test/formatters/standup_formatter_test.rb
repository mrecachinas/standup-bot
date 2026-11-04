require "test_helper"

class StandupFormatterTest < ActiveSupport::TestCase
  test "format_question shows just the question in bold" do
    assert_equal "*What did you work on yesterday?*", StandupFormatter.format_question("What did you work on yesterday?")
  end

  test "format_question uses the platform's bold syntax" do
    assert_equal "**Any blockers?**", StandupFormatter.format_question("Any blockers?", formatter: ChatPlatform::TeamsFormatter)
  end
end
