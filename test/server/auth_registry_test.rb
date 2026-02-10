# frozen_string_literal: true

ENV["APP_ENV"] = "test"

require "minitest/autorun"
require_relative "../../lib/server/auth_registry"

class AuthRegistryTest < Minitest::Test
  def setup
    # Clear registry before each test
    AuthRegistry.instance_variable_set(:@handlers, nil)
  end

  def test_register_and_list_methods
    AuthRegistry.register(:test_method, ->(_req) { {authenticated: true} })
    assert_equal [:test_method], AuthRegistry.available_methods
  end

  def test_authenticate_success
    AuthRegistry.register(:success, ->(_req) { {authenticated: true, email: "test@x.com"} })
    result = AuthRegistry.authenticate(nil)
    assert result[:authenticated]
    assert_equal "test@x.com", result[:email]
    assert_equal :success, result[:method]
  end

  def test_authenticate_fallback_to_second_method
    AuthRegistry.register(:fails, ->(_req) { {authenticated: false} })
    AuthRegistry.register(:succeeds, ->(_req) { {authenticated: true, email: "test@x.com"} })
    result = AuthRegistry.authenticate(nil)
    assert result[:authenticated]
    assert_equal :succeeds, result[:method]
  end

  def test_authenticate_failure_when_all_fail
    AuthRegistry.register(:fails1, ->(_req) { {authenticated: false} })
    AuthRegistry.register(:fails2, ->(_req) { {authenticated: false} })
    result = AuthRegistry.authenticate(nil)
    refute result[:authenticated]
    assert_equal "Authentication required", result[:error]
  end

  def test_authenticate_returns_first_actionable_failure
    AuthRegistry.register(:google_oauth, ->(_req) { {authenticated: false, error: "Email not authorized", status_code: 403} })
    AuthRegistry.register(:api_bearer, ->(_req) { {authenticated: false} })

    result = AuthRegistry.authenticate(nil)
    refute result[:authenticated]
    assert_equal "Email not authorized", result[:error]
    assert_equal 403, result[:status_code]
    assert_equal :google_oauth, result[:method]
  end

  def test_authenticate_no_methods_configured
    result = AuthRegistry.authenticate(nil)
    refute result[:authenticated]
    assert_equal "No authentication methods configured", result[:error]
  end
end
