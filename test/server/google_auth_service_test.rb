require "minitest/autorun"
require "test_helper"
require_relative "../../lib/server/google_auth_service"

class GoogleAuthServiceTest < Minitest::Test
  KEY = OpenSSL::PKey::RSA.generate(2048)
  KEY_ID = "test-key"

  def setup
    @service = Object.new.extend(GoogleAuthService)
    certificate = OpenSSL::X509::Certificate.new
    certificate.subject = certificate.issuer = OpenSSL::X509::Name.parse("/CN=OAuth test")
    certificate.public_key = KEY.public_key
    certificate.not_before = Time.now - 60
    certificate.not_after = Time.now + 60
    certificate.sign(KEY, OpenSSL::Digest.new("SHA256"))
    stub_request(:get, GoogleAuthService::GOOGLE_CERTS_URL).to_return(body: JSON.generate(KEY_ID => certificate.to_pem))
  end

  def test_specific_token_validation_errors
    {
      {exp: Time.now.to_i - 60} => "Token expired",
      {aud: "wrong-audience"} => "Token audience mismatch",
      {iss: "https://invalid.example"} => "Invalid token issuer"
    }.each do |claims, message|
      assert_equal({error: message}, @service.validate_token(signed_token(**claims)))
    end
  end

  private

  def signed_token(**claims)
    payload = {
      email: "test@example.com", email_verified: true, name: "Test",
      exp: Time.now.to_i + 60, aud: GoogleAuthService::GOOGLE_CLIENT_ID, iss: "https://accounts.google.com"
    }.merge(claims)
    JWT.encode(payload, KEY, "RS256", kid: KEY_ID)
  end
end
