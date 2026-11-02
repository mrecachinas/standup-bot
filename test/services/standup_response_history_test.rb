require "test_helper"

class StandupResponseHistoryTest < ActiveSupport::TestCase
  setup do
    @standup = standups(:daily)
  end

  test "shows history for selected date range" do
    history = StandupResponseHistory.new(
      standup: @standup,
      params: { start_date: "2025-04-06", end_date: "2025-04-06" },
      today: Date.new(2025, 4, 10)
    )

    assert_equal [ Date.new(2025, 4, 6) ], history.days.map(&:date)
    assert history.days.first.entries.any? { |entry| entry.platform_user_id == "U123456" && entry.answered? }
  end

  test "filters history to selected participant" do
    history = StandupResponseHistory.new(
      standup: @standup,
      params: { start_date: "2025-04-06", end_date: "2025-04-06", participant: "U234567" },
      today: Date.new(2025, 4, 10)
    )

    assert_equal [ "U234567" ], history.days.flat_map(&:entries).map(&:platform_user_id).uniq
  end

  test "filters visible answers to selected question" do
    history = StandupResponseHistory.new(
      standup: @standup,
      params: { start_date: "2025-04-06", end_date: "2025-04-06", question: "Any blockers?" },
      today: Date.new(2025, 4, 10)
    )

    john_entry = history.days.first.entries.find { |entry| entry.platform_user_id == "U123456" }

    assert_equal [ "Any blockers?" ], john_entry.answers.map(&:question)
    assert_equal [ "None" ], john_entry.answers.map(&:text)
  end

  test "marks expected participants as missed when no response exists" do
    history = StandupResponseHistory.new(
      standup: @standup,
      params: { start_date: "2025-04-07", end_date: "2025-04-07" },
      today: Date.new(2025, 4, 10)
    )

    assert_equal 2, history.summary[:missed]
    assert history.days.first.entries.select(&:expected?).all?(&:missed?)
  end

  test "detects responses updated after submission" do
    @standup.standup_participants.create!(
      platform_user_id: "UUPDATED159",
      display_name: "Updated Person",
      active: true
    )
    response = StandupResponse.create!(
      standup: @standup,
      platform_user_id: "UUPDATED159",
      status: "completed",
      answers: [
        {
          "question" => "What did you do yesterday?",
          "answer" => "Edited the response history",
          "timestamp" => "2025-04-08T09:05:00Z"
        }
      ],
      standup_date: Date.new(2025, 4, 8),
      created_at: Time.zone.local(2025, 4, 8, 9, 0, 0)
    )
    response.update_column(:updated_at, Time.zone.local(2025, 4, 8, 11, 0, 0))

    history = StandupResponseHistory.new(
      standup: @standup,
      params: { start_date: "2025-04-08", end_date: "2025-04-08", participant: "UUPDATED159" },
      today: Date.new(2025, 4, 10)
    )

    assert history.days.first.entries.first.updated_after_create?
  end

  test "schedule exceptions remove skipped dates from expected history" do
    @standup.standup_schedule_exceptions.create!(
      exception_type: "cancelled",
      original_date: Date.new(2026, 5, 1),
      reason: "One-off cancellation"
    )

    history = StandupResponseHistory.new(
      standup: @standup,
      params: { start_date: "2026-05-01", end_date: "2026-05-01" },
      today: Date.new(2026, 5, 1)
    )

    assert_empty history.days
    assert_equal 0, history.summary[:expected]
  end

  test "today's run isn't missed before it goes out" do
    @standup.standup_responses.delete_all
    history = StandupResponseHistory.new(
      standup: @standup,
      params: { start_date: "2025-04-10", end_date: "2025-04-10" },
      today: Date.new(2025, 4, 10)
    )

    entries = history.days.first.entries.select(&:expected?)
    assert entries.any?
    assert entries.all?(&:upcoming?)
    assert entries.none?(&:missed?)
    assert_equal "Upcoming", entries.first.status_label
    assert_equal 0, history.summary[:expected]
    assert_equal 0, history.summary[:missed]
  end

  test "summary counts add up to expected" do
    participants = @standup.standup_participants.active.order(:platform_user_id).to_a
    @standup.standup_responses.delete_all
    date = Date.new(2025, 4, 8)
    @standup.standup_responses.create!(platform_user_id: participants[0].platform_user_id, status: "completed", standup_date: date, answers: [])
    @standup.standup_responses.create!(platform_user_id: participants[1].platform_user_id, status: "skipped", standup_date: date, answers: [])
    @standup.standup_responses.create!(platform_user_id: "UEXPIRED1", status: "expired", standup_date: date, answers: [])

    history = StandupResponseHistory.new(
      standup: @standup,
      params: { start_date: "2025-04-08", end_date: "2025-04-08" },
      today: Date.new(2025, 4, 10)
    )
    summary = history.summary
    expired = history.days.first.entries.find { |entry| entry.platform_user_id == "UEXPIRED1" }

    assert_equal 1, summary[:answered]
    assert_equal 1, summary[:skipped]
    assert_equal summary[:expected], summary[:answered] + summary[:skipped] + summary[:pending] + summary[:missed]
    assert expired.missed?
    assert_equal "Missed", expired.status_label
  end
end
