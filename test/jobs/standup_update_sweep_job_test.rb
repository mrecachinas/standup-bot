require "test_helper"

class StandupUpdateSweepJobTest < ActiveJob::TestCase
  setup do
    @participant = standup_participants(:one)
    StandupResponse.where(platform_user_id: @participant.platform_user_id).delete_all
  end

  def run!(**attributes)
    StandupResponse.create!(standup: @participant.standup, platform_user_id: @participant.platform_user_id, status: "completed",
      standup_date: Date.current, answers: [ { "question" => "Q1", "answer" => "A1" } ], prompted_at: 1.hour.ago, **attributes)
  end

  test "finishes runs whose update or sign-off never went out" do
    stuck = run!(updated_at: 20.minutes.ago)

    assert_enqueued_with(job: StandupUpdateJob, args: [ stuck, { announce: true } ]) do
      StandupUpdateSweepJob.perform_now
    end
  end

  test "leaves runs that are signed off, just finished, or from before prompts were recorded" do
    run!(updated_at: 20.minutes.ago, signed_off_at: 20.minutes.ago)
    run!(updated_at: 1.minute.ago, standup_date: Date.current - 1)
    run!(updated_at: 20.minutes.ago, prompted_at: nil, standup_date: Date.current - 2)

    assert_no_enqueued_jobs(only: StandupUpdateJob) { StandupUpdateSweepJob.perform_now }
  end

  test "sends a next question that never went out after an answer was saved" do
    asked_at = 1.hour.ago.change(usec: 0)
    stuck = run!(status: "pending", prompted_at: asked_at, updated_at: 10.minutes.ago,
      answers: [ { "question" => "Q1", "answer" => "A1", "asked_at" => asked_at.iso8601(6) } ])

    assert_enqueued_with(job: StandupPromptJob, args: [ stuck, 1 ]) { StandupUpdateSweepJob.perform_now }
  end

  test "leaves pending runs whose next question went out, or with answers from before send times were recorded" do
    asked_at = 1.hour.ago.change(usec: 0)
    run!(status: "pending", prompted_at: 30.minutes.ago, updated_at: 10.minutes.ago,
      answers: [ { "question" => "Q1", "answer" => "A1", "asked_at" => asked_at.iso8601(6) } ])
    run!(status: "pending", updated_at: 10.minutes.ago, standup_date: Date.current - 1)
    run!(status: "pending", prompted_at: asked_at, updated_at: 1.minute.ago, standup_date: Date.current - 2,
      answers: [ { "question" => "Q1", "answer" => "A1", "asked_at" => asked_at.iso8601(6) } ])

    assert_no_enqueued_jobs(only: StandupPromptJob) { StandupUpdateSweepJob.perform_now }
  end
end
