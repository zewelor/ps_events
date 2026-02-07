# frozen_string_literal: true

# ApiAuthService - handles Bearer token authentication for API access
# Parses API_KEYS environment variable (format: token1:email1,token2:email2)
module ApiAuthService
  extend self

  class InvalidFormatError < StandardError; end

  def load_keys!(csv_string)
    @keys = {}
    return if csv_string.nil? || csv_string.strip.empty?

    pairs = csv_string.split(",").map(&:strip)

    pairs.each_with_index do |pair, index|
      validate_pair!(pair, index)
      token, email = pair.split(":", 2).map(&:strip)
      @keys[token] = email
    end

    unless ENV["APP_ENV"] == "test"
      puts "✅ ApiAuthService: Loaded #{@keys.size} API key(s)"
    end
  rescue InvalidFormatError => e
    unless ENV["APP_ENV"] == "test"
      puts "❌ ApiAuthService: Failed to load keys - #{e.message}"
    end
    raise
  end

  def enabled?
    @keys && !@keys.empty?
  end

  def validate_token(token)
    return {authenticated: false} unless enabled?
    return {authenticated: false} if token.nil? || token.strip.empty?

    submitter = @keys[token]
    if submitter
      {authenticated: true, email: submitter}
    else
      {authenticated: false}
    end
  end

  private

  def validate_pair!(pair, index)
    unless pair.include?(":")
      raise InvalidFormatError, "Pair #{index + 1} missing colon separator: '#{pair}'"
    end

    token, email = pair.split(":", 2).map(&:strip)

    if token.nil? || token.empty?
      raise InvalidFormatError, "Pair #{index + 1} has empty token: '#{pair}'"
    end

    if email.nil? || email.empty?
      raise InvalidFormatError, "Pair #{index + 1} has empty email: '#{pair}'"
    end

    unless email.include?("@")
      raise InvalidFormatError, "Pair #{index + 1} has invalid email format: '#{email}'"
    end
  end
end
