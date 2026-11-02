require "test_helper"

class Api::AuthorizationProbeController < Api::BaseController
  before_action :require_manager!

  def unchecked
    head :ok
  end

  def skipped
    skip_authorization
    head :ok
  end
end

class Api::AuthorizationCheckTest < ActionDispatch::IntegrationTest
  test "raises when an action never checks authorization" do
    with_probe_routes do
      assert_raises(Api::BaseController::AuthorizationNotPerformed) { get "/probe/unchecked", headers: token_headers }
    end
  end

  test "allows actions that explicitly skip authorization" do
    with_probe_routes do
      get "/probe/skipped", headers: token_headers
      assert_response :ok
    end
  end

  test "every /api controller keeps the authorization check" do
    unchecked = Rails.application.routes.routes.filter_map do |route|
      controller = route.defaults[:controller]
      next unless controller&.start_with?("api/")

      klass = "#{controller.camelize}Controller".safe_constantize
      next "#{controller} (missing controller)" unless klass
      next "#{controller} (doesn't inherit Api::BaseController)" unless klass <= Api::BaseController

      check = klass._process_action_callbacks.find { |callback| callback.kind == :after && callback.filter == :verify_authorized }
      conditional = check && (check.instance_variable_get(:@if).any? || check.instance_variable_get(:@unless).any?)
      "#{controller} (skips verify_authorized)" if check.nil? || conditional
    end

    assert_empty unchecked.uniq
  end

  private

  def with_probe_routes
    with_routing do |set|
      set.draw do
        get "/probe/unchecked", to: "api/authorization_probe#unchecked"
        get "/probe/skipped", to: "api/authorization_probe#skipped"
      end
      yield
    end
  end
end
