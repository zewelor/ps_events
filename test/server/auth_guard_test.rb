ENV["APP_ENV"] = "test"

require "minitest/autorun"
require_relative "../test_helper"
require_relative "../../lib/server/auth_guard"

class AuthGuardTest < Minitest::Test
  def test_missing_token
    result = AuthGuard.authenticate_google_token(nil)
    assert_equal false, result[:authenticated]
    assert_equal 401, result[:status_code]
  end

  def test_blank_token_with_custom_message
    result = AuthGuard.authenticate_google_token("  ", missing_message: "Custom required")
    assert_equal false, result[:authenticated]
    assert_equal "Custom required", result[:error]
    assert_equal 401, result[:status_code]
  end

  def test_invalid_token
    GoogleAuthService.stub :validate_token, {success: false, error: "Invalid token"} do
      result = AuthGuard.authenticate_google_token("bad")
      assert_equal false, result[:authenticated]
      assert_equal 401, result[:status_code]
      assert_includes result[:error], "Invalid token"
    end
  end

  def test_non_whitelisted_email_rejected
    GoogleAuthService.stub :validate_token, {success: true, email: "user@example.com"} do
      result = AuthGuard.authenticate_google_token("token")
      assert_equal false, result[:authenticated]
      assert_equal 403, result[:status_code]
      assert_equal "Email not authorized", result[:error]
    end
  end

  def test_whitelisted_email_accepted
    email = SecurityService::WHITELISTED_EMAILS.first
    GoogleAuthService.stub :validate_token, {success: true, email: email} do
      result = AuthGuard.authenticate_google_token("token")
      assert_equal true, result[:authenticated]
      assert_equal email, result[:email]
    end
  end
end
