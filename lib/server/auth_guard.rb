# frozen_string_literal: true

require_relative "google_auth_service"
require_relative "security_service"

# AuthGuard - single place for Google token + whitelist checks.
# Used by Sinatra endpoints and the AuthRegistry google_oauth handler
# so the rules cannot drift between /add_event, /event_image and /events_ocr.
module AuthGuard
  extend self

  def authenticate_google_token(google_token, missing_message: "Google authentication required")
    if google_token.nil? || google_token.strip.empty?
      return {authenticated: false, error: missing_message, status_code: 401}
    end

    auth = GoogleAuthService.validate_token(google_token)
    unless auth[:success]
      return {
        authenticated: false,
        error: "Google authentication failed: #{auth[:error] || "Invalid token"}",
        status_code: 401
      }
    end

    unless SecurityService.is_valid?(auth[:email])
      return {authenticated: false, error: "Email not authorized", status_code: 403}
    end

    {authenticated: true, email: auth[:email]}
  end
end
