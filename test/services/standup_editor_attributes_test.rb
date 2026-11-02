require "test_helper"

class StandupEditorAttributesTest < ActiveSupport::TestCase
  def convert(attributes)
    StandupEditorAttributes.new(attributes)
  end

  test "script attributes pass through untouched" do
    attributes = { "name" => "API", "schedule_type" => "daily", "default_hour" => 9 }

    assert_equal attributes, convert(attributes).attributes
  end

  test "the day picker becomes the matching schedule type" do
    assert_equal [ "daily", [] ], convert("frequency" => "weekly", "days" => (0..6).to_a).attributes.values_at("schedule_type", "schedule_days")
    assert_equal [ "weekdays", [] ], convert("frequency" => "weekly", "days" => %w[1 2 3 4 5]).attributes.values_at("schedule_type", "schedule_days")
    assert_equal [ "weekly", [ 3 ] ], convert("frequency" => "weekly", "days" => [ "3" ]).attributes.values_at("schedule_type", "schedule_days")
    assert_equal [ "custom", [ 1, 3 ] ], convert("frequency" => "weekly", "days" => [ 3, 1, 3 ]).attributes.values_at("schedule_type", "schedule_days")
  end

  test "reports schedule errors the model can't see" do
    assert_equal "Pick at least one day.", convert("frequency" => "weekly", "days" => []).schedule_error
    assert_equal "Every other week runs on one day. Pick a single day.", convert("frequency" => "biweekly", "days" => [ 1, 2 ]).schedule_error
  end

  test "send time and question rows map onto columns" do
    attributes = convert("send_time" => "9:30", "question_rows" => [ " First ", "", "Second" ]).attributes

    assert_equal [ 9, 30 ], attributes.values_at("default_hour", "default_minute")
    assert_equal [ "First", "Second" ], attributes["questions"]
    assert_not attributes.key?("send_time")
    assert_not attributes.key?("question_rows")
  end
end
