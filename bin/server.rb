#!/usr/bin/env ruby

# Sinatra environment is driven by RACK_ENV. Our containers set APP_ENV, so
# make sure production doesn't silently run as :development.
if ENV["RACK_ENV"].to_s.strip.empty? && !ENV["APP_ENV"].to_s.strip.empty?
  ENV["RACK_ENV"] = ENV["APP_ENV"]
end

require "bundler/setup"
require "json"
require "active_support/all" # Add this line
require "sinatra"

Bundler.require(:default)

# Load server modules
require_relative "../lib/server/google_sheets_service"
require_relative "../lib/server/event_validation"
require_relative "../lib/server/image_service"
require_relative "../lib/server/github_service"
require_relative "../lib/server/google_auth_service"
require_relative "../lib/server/security_service"
require_relative "../lib/server/event_ocr_service"
require_relative "../lib/server/add_event_service"
require_relative "../lib/server/auth_registry"
require_relative "../lib/server/api_auth_service"
require_relative "../lib/server/param_utils"

set :bind, "0.0.0.0"
set :port, ENV["PORT"] || 4567

# Helper methods for JSON responses
helpers do
  def json_response(data, status_code = 200)
    content_type :json
    status status_code
    data.to_json
  end

  def json_error(message, status_code = 422, errors = nil)
    response_data = {
      status: "error",
      message: message
    }
    response_data[:errors] = errors if errors
    json_response(response_data, status_code)
  end

  def json_success(message, data = {})
    response_data = {
      status: "ok",
      message: message
    }.merge(data)
    json_response(response_data, 200)
  end

  def upload_image_if_production(image_path)
    if settings.environment == :production
      GitHubService.upload_image(image_path)
      puts "✅ Image uploaded to GitHub (production)"
    else
      puts "ℹ️ Skipping GitHub upload (not in production environment)"
    end
  end

  def validate_event_image(event_image)
    return "" unless event_image && event_image[:tempfile]

    ImageService.validate_and_process(event_image)
  rescue => e
    puts "❌ Image processing error: #{e.message}"
    raise StandardError, "Image processing failed: #{e.message}"
  end

  def process_event_image(event_image)
    image_path = validate_event_image(event_image)
    upload_image_if_production(image_path)
    image_path
  end

  # Convert HTML5 date input (yyyy-mm-dd) to dd/mm/YYYY expected by the
  # validation layer. If the value is already in the desired format, it is
  # returned unchanged. Any parsing errors fall back to the original string.
  def normalize_date(date_str)
    return "" if date_str.nil?

    if /^\d{4}-\d{2}-\d{2}$/.match?(date_str)
      Date.strptime(date_str, "%Y-%m-%d").strftime("%d/%m/%Y")
    else
      date_str
    end
  rescue ArgumentError
    date_str
  end
end

# Initialize Google Sheets service
configure do
  if ENV["APP_ENV"] == "test"
    # Avoid external dependencies when running tests
    set :google_sheets, nil
    set :spreadsheet_id, "test"
    set :events_range, "A:Z"
  else
    set :google_sheets, GoogleSheetsService.new
    set :spreadsheet_id, ENV.fetch("GOOGLE_SPREADSHEET_ID")
    set :events_range, ENV.fetch("EVENTS_SHEET_RANGE")
  end
end

configure :production do
  set :host_authorization, {permitted_hosts: [".pxopulse.com"]}
end

configure do
  set :allowed_origin,
    ENV.fetch("ALLOWED_ORIGIN", "https://pxopulse.com") # overridden in development via docker-compose
end

# Register authentication methods
configure do
  # Google OAuth - always available
  AuthRegistry.register(:google_oauth, lambda do |request|
    # Skip in development mode
    return {authenticated: false} if settings.environment == :development

    params = request.params
    google_token = ParamUtils.fetch(params, :google_token)
    unless google_token && !google_token.strip.empty?
      return {authenticated: false}
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
  end)

  # API Bearer token - only if API_KEYS configured
  api_keys = ENV["API_KEYS"]
  if api_keys && !api_keys.strip.empty?
    ApiAuthService.load_keys!(api_keys)

    AuthRegistry.register(:api_bearer, lambda do |request|
      auth_header = request.env["HTTP_AUTHORIZATION"]
      return {authenticated: false} unless auth_header&.start_with?("Bearer ")

      token = auth_header.sub("Bearer ", "").strip
      ApiAuthService.validate_token(token)
    end)

    unless ENV["APP_ENV"] == "test"
      puts "✅ API Bearer authentication registered"
    end
  else
    unless ENV["APP_ENV"] == "test"
      puts "ℹ️ API Bearer authentication not registered (no API_KEYS configured)"
    end
  end

  unless ENV["APP_ENV"] == "test"
    puts "Available auth methods: #{AuthRegistry.available_methods.join(", ")}"
  end
end

# Enable CORS for all routes, but only from the allowed origin
before do
  origin = request.env["HTTP_ORIGIN"]
  if origin && origin != settings.allowed_origin
    halt 403, json_error("Forbidden origin", 403)
  end
  headers "Access-Control-Allow-Origin" => settings.allowed_origin
end

# Preflight OPTIONS handler
options "*" do
  origin = request.env["HTTP_ORIGIN"]
  if origin && origin != settings.allowed_origin
    halt 403, json_error("Forbidden origin", 403)
  end
  response.headers["Access-Control-Allow-Origin"] = settings.allowed_origin
  response.headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS"
  response.headers["Access-Control-Allow-Headers"] = "Content-Type,Accept,Origin,Authorization"
  200
end

# Health check endpoint
get "/health" do
  json_response({
    status: "ok",
    timestamp: Time.now.iso8601,
    google_sheets_connected: !settings.google_sheets.nil?
  })
end

post "/event_image" do
  unless settings.environment == :development
    google_token = ParamUtils.fetch(params, :google_token)
    unless google_token && !google_token.strip.empty?
      return json_error("Google authentication required", 401)
    end

    auth = GoogleAuthService.validate_token(google_token)
    unless auth[:success]
      return json_error("Google authentication failed: #{auth[:error]}", 401)
    end

    unless SecurityService.is_valid?(auth[:email])
      return json_error("Email not authorized", 403)
    end
  end

  begin
    image_path = process_event_image(params[:event_image])
    json_success("Image uploaded", {filename: File.basename(image_path, ".*")})
  rescue => e
    json_error(e.message)
  end
end

post "/events_ocr" do
  # Authentication via AuthRegistry (supports Google OAuth or API Bearer)
  if settings.environment == :development
    user_email = "development@example.com"
  else
    auth_result = AuthRegistry.authenticate(request)
    unless auth_result[:authenticated]
      status_code = auth_result[:status_code] || 401
      return json_error(auth_result[:error] || "Authentication required", status_code)
    end
    user_email = auth_result[:email]
    puts "✅ Authenticated via #{auth_result[:method]}: #{user_email}"
  end

  begin
    use_image = params[:use_event_image]
    image_path = validate_event_image(params[:event_image])
    events = EventOcrService.call(image_path, retry_sleep: 5)

    ocr_submitter_email = user_email.sub("@", "+ocr@")
    service = AddEventService.new(
      google_sheets: settings.google_sheets,
      spreadsheet_id: settings.spreadsheet_id,
      events_range: settings.events_range
    )

    pp events

    # Ensure events is an array before calling .each, if it could be a single string from OCR
    appended_ranges = []
    Array(events).each do |ev|
      if ev.is_a?(Hash)
        result = service.add_event(ev,
          submitter_email: ocr_submitter_email,
          image_path: use_image ? image_path : "")
        appended_ranges << result.updates.updated_range if result&.updates&.updated_range
      end
    end

    upload_image_if_production(image_path) if use_image

    events_count = appended_ranges.size
    range_info = appended_ranges.any? ? " → #{appended_ranges.join(", ")}" : ""
    json_success("#{events_count} evento(s) processado(s) via OCR#{range_info}", {text: JSON.pretty_generate(events)})
  rescue => e
    pp events
    puts "❌ Error processing OCR: #{e.message}"
    json_error(e.message)
  end
end

# Handle form submissions to add new event
post "/add_event" do
  puts "📝 Received event submission with params: #{params.keys}"

  # Require Google token
  google_token = ParamUtils.fetch(params, :google_token)
  unless google_token && !google_token.strip.empty?
    puts "❌ No Google token provided"
    return json_error("Google authentication is required to submit an event", 401)
  end

  # Validate Google token (now required)
  auth_result = GoogleAuthService.validate_token(google_token)
  unless auth_result[:success]
    puts "❌ Google auth failed: #{auth_result[:error]}"
    return json_error("Google authentication failed: #{auth_result[:error]}", 401)
  end

  google_user_email = auth_result[:email]
  puts "✅ Google auth validated for: #{google_user_email}"

  # Remove the file upload from params for validation
  validation_params = params.dup
  validation_params.delete(:event_image)
  validation_params.delete(:google_token)

  image_path = "" # Initialize image_path

  # Convert dates from HTML5 format (yyyy-mm-dd) to the format expected by the
  # validator (dd/mm/YYYY). Other formats pass through unchanged.
  validation_params[:start_date] = normalize_date(validation_params[:start_date])
  validation_params[:end_date] = normalize_date(validation_params[:end_date])

  # Validate the event data using dry-validation directly
  result = EventValidation.call(validation_params)

  if result.success?
    validated_params = result.to_h
    puts "✅ Validation successful for event: #{validated_params[:name]}"

    # Process image only after successful validation
    begin
      image_path = process_event_image(params[:event_image])
    rescue => e
      return json_error(e.message)
    end

    contact_email = validated_params[:contact_email]&.strip&.downcase
    if contact_email != google_user_email.downcase
      puts "ℹ️ Event submitted by #{google_user_email} for contact #{contact_email}"
    end

    begin
      AddEventService.new(
        google_sheets: settings.google_sheets,
        spreadsheet_id: settings.spreadsheet_id,
        events_range: settings.events_range
      ).add_event(validated_params, submitter_email: google_user_email, image_path: image_path)

      puts "✅ Event successfully added to spreadsheet"

      json_success("Event added successfully", {
        event_name: validated_params[:name],
        event_date: validated_params[:start_date].strip
      })
    rescue => e
      puts "❌ Error adding event: #{e.message}"
      puts "   Backtrace: #{e.backtrace.first(3).join(" | ")}"
      json_error("Failed to add event. Please try again.", 500)
    end
  else
    puts "❌ Validation failed: #{result.errors.to_h.inspect}"
    # Validation failed: return errors as JSON
    json_error("Validation failed\n#{result.errors.to_h.map { |k, v| "#{k}: #{v.join(", ")}" }.join("\n")}", 422)
  end
end
