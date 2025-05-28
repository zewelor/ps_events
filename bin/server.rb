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
end

# Initialize Google Sheets service
configure do
  set :google_sheets, GoogleSheetsService.new
  set :spreadsheet_id, ENV.fetch("GOOGLE_SPREADSHEET_ID")
  set :events_range, ENV.fetch("EVENTS_SHEET_RANGE")
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
  image_path = ""
  if params[:event_image] && params[:event_image][:tempfile]
    begin
      # Validate the image
      validation_error = ImageService.validate_upload(params[:event_image])
      if validation_error
        return json_error(validation_error)
      end

      # Process the image
      image_path = ImageService.process_upload(params[:event_image])
      puts "✅ Image processed successfully: #{image_path}"

      # Upload to GitHub only in production environment
      if settings.environment == :production
        # Get the full file path for GitHub upload
        full_image_path = File.join(File.dirname(__FILE__), "..", "events_listing", image_path)
        GitHubService.upload_image(full_image_path)
        puts "✅ Image uploaded to GitHub (production)"
      else
        puts "ℹ️ Skipping GitHub upload (not in production environment)"
      end
    rescue => e
      puts "❌ Image processing error: #{e.message}"
      return json_error("Image processing failed: #{e.message}")
    end
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

    # Format start and end times using helper method
    start_str = format_datetime(validated_params[:start_date], validated_params[:start_time])
    end_str = format_datetime(validated_params[:end_date], validated_params[:end_time])

    # Format submitted at timestamp
    submitted_at = Time.now.strftime("%d/%m/%Y %H:%M")

    # Prepare event data for spreadsheet
    # Extract only filename from image_path if present (without extension)
    image_filename = image_path.empty? ? "" : File.basename(image_path, ".*")

    # Use Google authenticated email as submitter (who actually submitted)
    submitter_email = google_user_email

    # Use the provided contact email (which may be different from submitter)
    contact_email = validated_params[:contact_email].strip.downcase

    # Log if submitter and contact are different (for moderator cases)
    if contact_email != google_user_email.downcase
      puts "ℹ️ Event submitted by #{google_user_email} for contact #{contact_email}"
    end

    event_data = [
      submitted_at,
      submitter_email,
      validated_params[:name].strip,
      start_str,
      end_str,
      validated_params[:location].strip,
      validated_params[:description].strip,
      validated_params[:category].strip,
      validated_params[:organizer].strip,
      contact_email, # Use the provided contact email
      validated_params[:contact_tel]&.strip || "",
      validated_params[:price_type]&.strip || "",
      image_filename, # Store only the filename
      validated_params[:event_link1]&.strip || "",
      validated_params[:event_link2]&.strip || "",
      validated_params[:event_link3]&.strip || "",
      validated_params[:event_link4]&.strip || ""
    ]

    # Log the event data (mask sensitive info)
    masked_data = event_data.dup
    masked_data[1] = "#{masked_data[1].split("@").first}@***" if masked_data[1].include?("@") # submitter
    masked_data[9] = "#{masked_data[9].split("@").first}@***" if masked_data[9].include?("@") # contact
    puts "✅ Adding event: #{masked_data[2]} by #{masked_data[8]} at #{masked_data[3]} (submitted by #{masked_data[1]}, contact: #{masked_data[9]})"

    begin
      # Add to Google Sheets
      settings.google_sheets.append_row(
        settings.spreadsheet_id,
        settings.events_range,
        event_data
      )

      puts "✅ Event successfully added to spreadsheet"

      # Respond with JSON status
      json_success("Event added successfully", {
        event_name: validated_params[:name],
        event_date: start_str
      })
    rescue => e
      puts "❌ Error adding event: #{e.message}"
      puts "   Backtrace: #{e.backtrace.first(3).join(" | ")}"
      json_error("Failed to add event. Please try again.", 500)
    end
  else
    puts "❌ Validation failed: #{result.errors.to_h.inspect}"
    # Validation failed: return errors as JSON
    json_error("Validation failed", 422, result.errors.to_h)
  end
end
