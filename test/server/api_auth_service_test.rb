# frozen_string_literal: true

ENV["APP_ENV"] = "test"

require "minitest/autorun"
require_relative "../../lib/server/api_auth_service"

class ApiAuthServiceTest < Minitest::Test
  def setup
    # Reset state before each test
    ApiAuthService.instance_variable_set(:@keys, nil)
  end

  def test_load_single_key
    capture_io { ApiAuthService.load_keys!("token123:api@example.com") }
    assert ApiAuthService.enabled?
    result = ApiAuthService.validate_token("token123")
    assert result[:authenticated]
    assert_equal "api@example.com", result[:email]
  end

  def test_load_multiple_keys
    capture_io { ApiAuthService.load_keys!("token1:email1@x.com,token2:email2@y.pl") }
    assert ApiAuthService.enabled?
    assert_equal "email1@x.com", ApiAuthService.validate_token("token1")[:email]
    assert_equal "email2@y.pl", ApiAuthService.validate_token("token2")[:email]
  end

  def test_invalid_token
    capture_io { ApiAuthService.load_keys!("valid:email@x.com") }
    result = ApiAuthService.validate_token("invalid")
    refute result[:authenticated]
  end

  def test_empty_token
    capture_io { ApiAuthService.load_keys!("valid:email@x.com") }
    result = ApiAuthService.validate_token("")
    refute result[:authenticated]
  end

  def test_nil_token
    capture_io { ApiAuthService.load_keys!("valid:email@x.com") }
    result = ApiAuthService.validate_token(nil)
    refute result[:authenticated]
  end

  def test_not_enabled_without_keys
    refute ApiAuthService.enabled?
    result = ApiAuthService.validate_token("anything")
    refute result[:authenticated]
  end

  def test_invalid_format_missing_colon
    error = assert_raises(ApiAuthService::InvalidFormatError) do
      capture_io { ApiAuthService.load_keys!("invalid_pair") }
    end
    assert_includes error.message, "missing colon separator"
  end

  def test_invalid_format_empty_token
    error = assert_raises(ApiAuthService::InvalidFormatError) do
      capture_io { ApiAuthService.load_keys!(":email@x.com") }
    end
    assert_includes error.message, "empty token"
  end

  def test_invalid_format_empty_email
    error = assert_raises(ApiAuthService::InvalidFormatError) do
      capture_io { ApiAuthService.load_keys!("token:") }
    end
    assert_includes error.message, "empty email"
  end

  def test_invalid_format_bad_email
    error = assert_raises(ApiAuthService::InvalidFormatError) do
      capture_io { ApiAuthService.load_keys!("token:not_an_email") }
    end
    assert_includes error.message, "invalid email format"
  end

  def test_load_keys_raises_on_invalid_format
    assert_raises(ApiAuthService::InvalidFormatError) do
      capture_io { ApiAuthService.load_keys!("invalid_pair") }
    end
  end
end
