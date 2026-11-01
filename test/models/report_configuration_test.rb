require "test_helper"

class ReportConfigurationTest < ActiveSupport::TestCase
  test "normalizes delivery channel and recipients from form text" do
    configuration = ReportConfiguration.new(
      standup: standups(:weekly),
      delivery_channel: " #weekly-reports ",
      recipients_text: " UREPORT1 \n#team-reports\nUREPORT1",
      report_format: "slack",
      detail_level: "summary"
    )

    assert configuration.valid?
    assert_equal "weekly-reports", configuration.delivery_channel
    assert_equal [ "UREPORT1", "team-reports" ], configuration.recipients
  end

  test "rejects malformed delivery channel and recipients" do
    configuration = ReportConfiguration.new(
      standup: standups(:weekly),
      delivery_channel: "bad channel",
      recipients: [ "UGOOD1", "bad recipient" ],
      report_format: "slack",
      detail_level: "summary"
    )

    assert_not configuration.valid?
    assert_includes configuration.errors[:delivery_channel], "must be a Slack channel name or ID without spaces"
    assert_includes configuration.errors[:recipients].join, "bad recipient"
  end
end
