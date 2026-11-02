require "test_helper"

class PercentageTest < ActiveSupport::TestCase
  test "rounds to one decimal place" do
    assert_equal 66.7, Percentage.of(2, 3)
  end

  test "returns the empty value when there's nothing to divide by" do
    assert_equal 0.0, Percentage.of(0, 0)
    assert_nil Percentage.of(1, 0, empty: nil)
  end
end
