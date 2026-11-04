require "test_helper"

class SlackSocketMode::PresenceTest < ActiveSupport::TestCase
  setup do
    @cache = ActiveSupport::Cache::MemoryStore.new
    @outages = 0
    @ready_file = Rails.root.join("tmp", "presence-test-#{SecureRandom.hex(4)}.ready").to_s
    @presence = SlackSocketMode::Presence.new(cache: @cache, ready_file: @ready_file, on_outage: -> { @outages += 1 })
  end

  teardown { FileUtils.rm_f(@ready_file) }

  test "backfills when no client has been connected recently" do
    @presence.connected!
    assert_equal 1, @outages, "nothing recorded yet"

    @presence.connected!
    assert_equal 1, @outages, "another client was just connected"

    Timecop.travel(3.minutes.from_now) { @presence.connected! }
    assert_equal 2, @outages
  end

  test "keeps a ready file while connected" do
    @presence.connected!
    assert File.exist?(@ready_file)

    @presence.disconnected!
    assert_not File.exist?(@ready_file)
  end
end
