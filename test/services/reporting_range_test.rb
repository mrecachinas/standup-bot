require "test_helper"

class ReportingRangeTest < ActiveSupport::TestCase
  def build(start_date: nil, end_date: nil, max_days: 30)
    ReportingRange.from_params(
      start_date: start_date,
      end_date: end_date,
      default_end: Date.new(2025, 4, 30),
      default_start: ->(end_date) { end_date - 6 },
      max_days: max_days
    )
  end

  test "falls back to the defaults for missing or unparseable dates" do
    range = build(start_date: "not-a-date")

    assert_equal [ Date.new(2025, 4, 24), Date.new(2025, 4, 30) ], [ range.start_date, range.end_date ]
    assert_not range.limited?
  end

  test "swaps a reversed range" do
    range = build(start_date: "2025-04-10", end_date: "2025-04-01")

    assert_equal [ Date.new(2025, 4, 1), Date.new(2025, 4, 10) ], [ range.start_date, range.end_date ]
  end

  test "keeps the most recent days of a range that's too long" do
    range = build(start_date: "2025-01-01", end_date: "2025-04-30", max_days: 30)

    assert range.limited?
    assert_equal Date.new(2025, 4, 1), range.start_date
    assert_equal 30, (range.end_date - range.start_date).to_i + 1
  end

  test "parse_date accepts dates and ISO strings only" do
    assert_equal Date.new(2025, 4, 1), ReportingRange.parse_date(Date.new(2025, 4, 1))
    assert_equal Date.new(2025, 4, 1), ReportingRange.parse_date("2025-04-01")
    assert_nil ReportingRange.parse_date("April 1")
    assert_nil ReportingRange.parse_date("")
  end
end
