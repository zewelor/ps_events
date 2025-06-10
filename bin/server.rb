#!/usr/bin/env ruby

require "bundler/setup"
require "json"

Bundler.require(:default)

# Load server modules
require_relative "../lib/server/google_sheets_service"
require_relative "../lib/server/event_validation"
require_relative "../lib/server/image_service"
require_relative "../lib/server/github_service"
require_relative "../lib/server/google_auth_service"
require_relative "../lib/server/security_service"
require_relative "../lib/server/event_ocr_service"

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

  def format_datetime(date_str, time_str = nil)
    date = Date.parse(date_str)
    if time_str && !time_str.strip.empty?
      DateTime.parse("#{date_str} #{time_str}").strftime("%d/%m/%Y %H:%M")
    else
      date.strftime("%d/%m/%Y")
    end
  end

  def process_event_image(event_image)
    return "" unless event_image && event_image[:tempfile]

    begin
      # Validate the image
      validation_error = ImageService.validate_upload(event_image)
      if validation_error
        raise StandardError, validation_error
      end

      # Process the image
      image_path = ImageService.process_upload(event_image)
      puts "✅ Image processed successfully: #{image_path}"

      # Upload to GitHub only in production environment
      if settings.environment == :production
        # Get the full file path for GitHub upload
        GitHubService.upload_image(image_path)
        puts "✅ Image uploaded to GitHub (production)"
      else
        puts "ℹ️ Skipping GitHub upload (not in production environment)"
      end

      image_path
    rescue => e
      puts "❌ Image processing error: #{e.message}"
      raise StandardError, "Image processing failed: #{e.message}"
    end
  end

  def add_event_to_sheet(validated_params, submitter_email, image_path = "")
    start_date_str = Date.parse(validated_params[:start_date]).strftime("%d/%m/%Y")
    start_time_str = validated_params[:start_time]&.strip || ""
    end_date_str = Date.parse(validated_params[:end_date]).strftime("%d/%m/%Y")
    end_time_str = validated_params[:end_time]&.strip || ""

    submitted_at = Time.now.strftime("%d/%m/%Y %H:%M")

    image_filename = image_path.empty? ? "" : File.basename(image_path, ".*")

    contact_email = validated_params[:contact_email]&.strip&.downcase

    event_data = [
      submitted_at,
      submitter_email,
      validated_params[:name].strip,
      start_date_str,
      start_time_str,
      end_date_str,
      end_time_str,
      validated_params[:location].strip,
      validated_params[:description].strip,
      validated_params[:category].strip,
      validated_params[:organizer].strip,
      contact_email,
      validated_params[:contact_tel]&.strip || "",
      validated_params[:price_type]&.strip || "",
      image_filename,
      validated_params[:event_link1]&.strip || "",
      validated_params[:event_link2]&.strip || "",
      validated_params[:event_link3]&.strip || "",
      validated_params[:event_link4]&.strip || ""
    ]

    masked_data = event_data.dup
    masked_data[1] = "#{masked_data[1].split("@").first}@***" if masked_data[1].include?("@")
    masked_data[11] = "#{masked_data[11].split("@").first}@***" if masked_data[11]&.include?("@")
    puts "✅ Adding event: #{masked_data[2]} by #{masked_data[10]} on #{masked_data[3]} #{masked_data[4]} (submitted by #{masked_data[1]}, contact: #{masked_data[11]})"

    settings.google_sheets.append_row(settings.spreadsheet_id, settings.events_range, event_data)
    event_data
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

# Enable CORS for all routes
before do
  headers "Access-Control-Allow-Origin" => "*"
end

# Preflight OPTIONS handler
options "*" do
  response.headers["Access-Control-Allow-Origin"] = "*"
  response.headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS"
  response.headers["Access-Control-Allow-Headers"] = "Content-Type,Accept,Origin"
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
    unless params[:google_token] && !params[:google_token].strip.empty?
      return json_error("Google authentication required", 401)
    end

    auth = GoogleAuthService.validate_token(params[:google_token])
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
  if settings.environment == :development
    auth = {email: "dev@example.com"}
  else
    unless params[:google_token] && !params[:google_token].strip.empty?
      return json_error("Google authentication required", 401)
    end

    auth = GoogleAuthService.validate_token(params[:google_token])
    unless auth[:success]
      return json_error("Google authentication failed: #{auth[:error]}", 401)
    end

    unless SecurityService.is_valid?(auth[:email])
      return json_error("Email not authorized", 403)
    end
  end

  begin
    image_path = process_event_image(params[:event_image])
    ocr = EventOcrService.new
    text = ocr.analyze(image_path)

    events = JSON.parse(text)
    validator = EventValidation.new
    added = []

    events.each do |event|
      event["start_date"] = begin
        Date.strptime(event["start_date"], "%d/%m/%Y").strftime("%Y-%m-%d")
      rescue
        next
      end
      event["end_date"] = begin
        Date.strptime(event["end_date"], "%d/%m/%Y").strftime("%Y-%m-%d")
      rescue
        next
      end
      result = validator.call(event)
      next unless result.success?

      add_event_to_sheet(result.to_h, auth[:email], image_path)
      added << result.to_h[:name]
    end

    json_success("OCR completed", {text: text, added: added})
  rescue JSON::ParserError => e
    json_error("Invalid OCR response: #{e.message}")
  rescue => e
    json_error(e.message)
  end
end

# Handle form submissions to add new event
post "/add_event" do
  puts "📝 Received event submission with params: #{params.keys}"

  # Require Google token
  unless params[:google_token] && !params[:google_token].strip.empty?
    puts "❌ No Google token provided"
    return json_error("Google authentication is required to submit an event", 401)
  end

  # Validate Google token (now required)
  auth_result = GoogleAuthService.validate_token(params[:google_token])
  unless auth_result[:success]
    puts "❌ Google auth failed: #{auth_result[:error]}"
    return json_error("Google authentication failed: #{auth_result[:error]}", 401)
  end

  google_user_email = auth_result[:email]
  puts "✅ Google auth validated for: #{google_user_email}"

  # Handle image upload first (if provided)
  begin
    image_path = process_event_image(params[:event_image])
  rescue => e
    return json_error(e.message)
  end

  # Remove the file upload from params for validation
  validation_params = params.dup
  validation_params.delete(:event_image)

  # Validate the event data using dry-validation directly
  validator = EventValidation.new
  result = validator.call(validation_params)

  if result.success?
    validated_params = result.to_h
    puts "✅ Validation successful for event: #{validated_params[:name]}"

    if validated_params[:contact_email] && validated_params[:contact_email].downcase != google_user_email.downcase
      puts "ℹ️ Event submitted by #{google_user_email} for contact #{validated_params[:contact_email]}"
    end

    begin
      add_event_to_sheet(validated_params, google_user_email, image_path)
      puts "✅ Event successfully added to spreadsheet"
      json_success("Event added successfully", {event_name: validated_params[:name], event_date: Date.parse(validated_params[:start_date]).strftime("%d/%m/%Y")})
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
