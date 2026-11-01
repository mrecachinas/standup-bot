# Include in an adapter's test case and define #adapter. Checks that the
# adapter implements every method in the ChatPlatform::Adapter contract.
module ChatPlatformAdapterContract
  CONTRACT_METHODS = %i[
    key label configured? formatter
    send_direct_message send_message post_standup_update update_standup_update post_report send_selection
    user_profile search_users list_channels channel_member_ids channel_member_profiles connection_status
    valid_user_id? normalize_user_id user_id_hint valid_channel? normalize_channel channel_hint
  ].freeze

  FORMATTER_METHODS = %i[bold italic code channel_reference].freeze

  def test_implements_the_adapter_contract
    assert_kind_of ChatPlatform::Adapter, adapter

    CONTRACT_METHODS.each do |method_name|
      owner = adapter.class.instance_method(method_name).owner
      assert_not_equal ChatPlatform::Adapter, owner, "#{adapter.class} must implement ##{method_name}"
    end
  end

  def test_formatter_implements_the_formatting_contract
    FORMATTER_METHODS.each do |method_name|
      assert_respond_to adapter.formatter, method_name
    end
  end

  def test_registered_under_its_key
    assert ChatPlatform.supported?(adapter.key)
    assert_instance_of adapter.class, ChatPlatform.for(adapter.key)
  end
end
