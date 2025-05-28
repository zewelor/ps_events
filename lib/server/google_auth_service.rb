require "json"
require "net/http"
require "jwt"
require "openssl"

module GoogleAuthService
  extend self

  GOOGLE_CLIENT_ID = ENV["GOOGLE_OAUTH_CLIENT_ID"]
  GOOGLE_CERTS_URL = "https://www.googleapis.com/oauth2/v1/certs"

  def validate_token(id_token)
    return {error: "No token provided"} if id_token.nil? || id_token.strip.empty?
    return {error: "Google Client ID not configured"} if GOOGLE_CLIENT_ID.nil?

    begin
      # Decode token header to get the key ID (kid)
      header = JWT.decode(id_token, nil, false)[1]
      kid = header["kid"]

      return {error: "Token missing key ID"} unless kid

      # Get Google's public keys
      public_keys = fetch_google_public_keys
      return {error: "Could not fetch Google public keys"} unless public_keys

      # Find the matching public key
      cert_data = public_keys[kid]
      return {error: "No matching public key found"} unless cert_data

      # Parse the certificate and extract the public key
      cert = OpenSSL::X509::Certificate.new(cert_data)
      public_key = cert.public_key

      # Verify and decode the JWT with the public key
      decoded_token = JWT.decode(
        id_token,
        public_key,
        true, # verify signature
        {
          algorithm: "RS256",
          aud: GOOGLE_CLIENT_ID,
          verify_aud: true,
          iss: ["https://accounts.google.com", "accounts.google.com"],
          verify_iss: true
        }
      )

      payload = decoded_token[0]

      # Return user info from the validated token
      {
        success: true,
        email: payload["email"],
        name: payload["name"],
        verified_email: payload["email_verified"] == true
      }
    rescue JWT::DecodeError => e
      {error: "Invalid token: #{e.message}"}
    rescue JWT::ExpiredSignature
      {error: "Token expired"}
    rescue JWT::InvalidAudError
      {error: "Token audience mismatch"}
    rescue JWT::InvalidIssuerError
      {error: "Invalid token issuer"}
    rescue => e
      {error: "Token validation failed: #{e.message}"}
    end
  end

  private

  def fetch_google_public_keys
    @keys_cache ||= {}
    @keys_cache_time ||= {}

    # Cache keys for 1 hour
    if @keys_cache_time[:google] && (Time.now - @keys_cache_time[:google]) < 3600
      return @keys_cache[:google]
    end

    begin
      uri = URI(GOOGLE_CERTS_URL)
      response = Net::HTTP.get_response(uri)

      if response.is_a?(Net::HTTPSuccess)
        @keys_cache[:google] = JSON.parse(response.body)
        @keys_cache_time[:google] = Time.now
        return @keys_cache[:google]
      end
    rescue => e
      puts "Failed to fetch Google public keys: #{e.message}"
    end

    nil
  end
end
