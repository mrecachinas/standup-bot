require "test_helper"

class Manager::AuthorizationProbeController < Manager::ApplicationController
  def unchecked
    head :ok
  end

  def skipped
    skip_authorization
    head :ok
  end
end

class Manager::AuthorizationCheckTest < ActionDispatch::IntegrationTest
  setup do
    Manager::AuthorizationProbeController.any_instance.stubs(:current_user).returns(users(:manager))
  end

  test "raises when an action never checks authorization" do
    with_probe_routes do
      assert_raises(Web::ApplicationController::AuthorizationNotPerformed) { get "/probe/unchecked" }
    end
  end

  test "allows actions that explicitly skip authorization" do
    with_probe_routes do
      get "/probe/skipped"
      assert_response :ok
    end
  end

  private

  def with_probe_routes
    with_routing do |set|
      set.draw do
        get "/probe/unchecked", to: "manager/authorization_probe#unchecked"
        get "/probe/skipped", to: "manager/authorization_probe#skipped"
      end
      yield
    end
  end
end
