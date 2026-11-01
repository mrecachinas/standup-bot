require "test_helper"

class ChartsHelperTest < ActionView::TestCase
  test "run breakdown chart renders a stacked bar group per run" do
    runs = [
      { date: Date.new(2026, 10, 1), expected: 4, completed: 3, skipped: 1, pending: 0, missed: 0, completion_rate: 75.0 },
      { date: Date.new(2026, 10, 2), expected: 4, completed: 2, skipped: 0, pending: 0, missed: 2, completion_rate: 50.0 }
    ]

    html = run_breakdown_chart(runs, width: 480)

    assert_includes html, 'viewBox="0 0 480 '
    assert_equal 2, html.scan('class="bar-group"').size
    assert_includes html, "Oct 2, 2026: 2 completed, 0 skipped, 2 missed (50%)"
  end

  test "charts show an empty state without data" do
    assert_includes run_breakdown_chart([]), "No standup runs in this period yet."
    assert_includes rate_line_chart([]), "Not enough data to chart yet."
  end

  test "sparkline needs at least two points" do
    assert_includes sparkline([ 50 ]), "—"
    assert_includes sparkline([ 50, 75, 100 ]), "<polyline"
  end
end
