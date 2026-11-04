require "test_helper"

class StandupUpdateJobTest < ActiveJob::TestCase
  setup do
    @participant = standup_participants(:one)
    @standup = @participant.standup
    @user_id = @participant.platform_user_id
    StandupResponse.where(platform_user_id: @user_id).delete_all
    @run = StandupResponse.create!(standup: @standup, platform_user_id: @user_id, status: "completed", standup_date: Date.current,
      answers: [ { "question" => "Q1", "answer" => "Shipped" } ])
    @dms = []
    ChatPlatform::SlackAdapter.any_instance.stubs(:send_direct_message).with { |user_id, text| @dms << [ user_id, text ]; true }
      .returns(ChatPlatform::MessageRef.new(channel: "D1", id: "9.9", sent_at: Time.zone.at(1_800_000_000)))
  end

  test "posts the update, then tells the person where it went" do
    ChatPlatform::SlackAdapter.any_instance.expects(:post_standup_update)
      .with(@standup.platform_channel, display_name: "John Doe", standup_name: @standup.name, answers: [ { question: "Q1", answer: "Shipped" } ], edited: false)
      .returns(ChatPlatform::MessageRef.new(channel: "C1", id: "post.1"))

    StandupUpdateJob.perform_now(@run, announce: true)

    assert_equal "post.1", @run.reload.platform_message_id
    assert_match(/Your update has been posted to #daily-standup\.\z/, @dms.sole.last)
    assert_equal Time.zone.at(1_800_000_000), @run.prompted_at
  end

  test "doesn't claim it posted anything when every answer was skipped" do
    @run.update!(answers: [ { "question" => "Q1", "answer" => "(skipped)" } ])
    ChatPlatform::SlackAdapter.any_instance.expects(:post_standup_update).never

    StandupUpdateJob.perform_now(@run, announce: true)

    assert_not_includes @dms.sole.last, "posted"
  end

  test "keeps the answers and tells the person and the admins when the channel can't be posted to" do
    ChatPlatform::SlackAdapter.any_instance.expects(:post_standup_update).raises(Slack::Web::Api::Errors::NotInChannel.new("not_in_channel"))
    StandupUpdateJob.any_instance.expects(:notify_admin_channel).with(instance_of(Slack::Web::Api::Errors::NotInChannel), has_entry(:context, regexp_matches(/couldn't post/)))

    assert_nothing_raised { StandupUpdateJob.perform_now(@run, announce: true) }

    assert_equal "completed", @run.reload.status
    assert_equal [ "Shipped" ], @run.answers.map { |answer| answer["answer"] }
    assert_match(/I couldn't post your update to #daily-standup \(not_in_channel\), but your answers are saved/, @dms.sole.last)
  end

  test "posts again when the old post was deleted" do
    @run.update!(platform_message_id: "post.1")
    ChatPlatform::SlackAdapter.any_instance.expects(:update_standup_update).raises(Slack::Web::Api::Errors::MessageNotFound.new("message_not_found"))
    ChatPlatform::SlackAdapter.any_instance.expects(:post_standup_update).returns(ChatPlatform::MessageRef.new(channel: "C1", id: "post.2"))

    StandupUpdateJob.perform_now(@run)

    assert_equal "post.2", @run.reload.platform_message_id
  end

  test "retries when Slack is rate limiting, without telling the person anything yet" do
    ChatPlatform::SlackAdapter.any_instance.expects(:post_standup_update).raises(Slack::Web::Api::Errors::TooManyRequestsError.new(Faraday::Response.new(status: 429, response_headers: { "retry-after" => "1" })))

    assert_enqueued_with(job: StandupUpdateJob) do
      StandupUpdateJob.perform_now(@run, announce: true)
    end
    assert_empty @dms
  end

  test "a retried sign-off still says where the update went" do
    @run.update!(platform_message_id: "post.1")
    ChatPlatform::SlackAdapter.any_instance.expects(:update_standup_update)

    StandupUpdateJob.perform_now(@run, announce: true)

    assert_match(/Your update has been posted to #daily-standup\./, @dms.sole.last)
    assert @run.reload.signed_off_at.present?
  end

  test "signs off only once" do
    @run.update!(platform_message_id: "post.1", signed_off_at: Time.current)
    ChatPlatform::SlackAdapter.any_instance.stubs(:update_standup_update)

    StandupUpdateJob.perform_now(@run, announce: true)

    assert_empty @dms
  end
end
