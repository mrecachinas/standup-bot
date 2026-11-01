require "test_helper"

class Microsoft::WindowsTimeZonesTest < ActiveSupport::TestCase
  test "maps Windows names and passes IANA names through" do
    assert_equal "America/Los_Angeles", Microsoft::WindowsTimeZones.to_iana("Pacific Standard Time")
    assert_equal "Europe/London", Microsoft::WindowsTimeZones.to_iana("GMT Standard Time")
    assert_equal "Asia/Tokyo", Microsoft::WindowsTimeZones.to_iana("Asia/Tokyo")
  end

  test "returns nil for unknown or blank names" do
    assert_nil Microsoft::WindowsTimeZones.to_iana("Mars Standard Time")
    assert_nil Microsoft::WindowsTimeZones.to_iana(nil)
  end

  test "every mapped zone is a valid IANA zone" do
    Microsoft::WindowsTimeZones::MAP.each_value do |zone|
      assert StandupParticipant.valid_timezone?(zone), "#{zone} isn't a valid time zone"
    end
  end
end
