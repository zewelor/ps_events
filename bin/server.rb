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
  content_type :json
  {
    status: "ok",
    timestamp: Time.now.iso8601,
    google_sheets_connected: !settings.google_sheets.nil?
  }.to_json
end

# Handle form submissions to add new event
post "/add_event" do
  puts "📝 Received event submission with params: #{params.keys}"

  # Validate Google token if provided
  google_user_email = nil
  if params[:google_token] && !params[:google_token].strip.empty?
    auth_result = GoogleAuthService.validate_token(params[:google_token])
    if auth_result[:success]
      google_user_email = auth_result[:email]
      puts "✅ Google auth validated for: #{google_user_email}"
    else
      puts "❌ Google auth failed: #{auth_result[:error]}"
      content_type :json
      status 401
      return {
        status: "error",
        message: "Google authentication failed: #{auth_result[:error]}"
      }.to_json
    end
  end

  # Handle image upload first (if provided)
  image_path = ""
  if params[:event_image] && params[:event_image][:tempfile]
    begin
      # Validate the image
      validation_error = ImageService.validate_upload(params[:event_image])
      if validation_error
        content_type :json
        status 422
        return {
          status: "error",
          message: validation_error
        }.to_json
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
      content_type :json
      status 422
      return {
        status: "error",
        message: "Image processing failed: #{e.message}"
      }.to_json
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

    # Format start and end times
    # Combine date and time if time is provided, otherwise use date only
    start_date = Date.parse(validated_params[:start_date])
    start_time = (validated_params[:start_time] && !validated_params[:start_time].strip.empty?) ?
                 validated_params[:start_time] : nil

    if start_time
      start_dt = DateTime.parse("#{validated_params[:start_date]} #{start_time}")
      start_str = start_dt.strftime("%d/%m/%Y %H:%M")
    else
      start_str = start_date.strftime("%d/%m/%Y")
    end

    # Handle end date and time
    end_date = Date.parse(validated_params[:end_date])
    end_time = (validated_params[:end_time] && !validated_params[:end_time].strip.empty?) ?
               validated_params[:end_time] : nil

    if end_time
      end_dt = DateTime.parse("#{validated_params[:end_date]} #{end_time}")
      end_str = end_dt.strftime("%d/%m/%Y %H:%M")
    else
      end_str = end_date.strftime("%d/%m/%Y")
    end

    # Format submitted at timestamp
    submitted_at = Time.now.strftime("%d/%m/%Y %H:%M")

    # Prepare event data for spreadsheet
    # Extract only filename from image_path if present (without extension)
    image_filename = image_path.empty? ? "" : File.basename(image_path, ".*")

    # Use Google authenticated email or fallback
    submitter_email = google_user_email || "UNKNOWN"

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
      validated_params[:contact_email].strip.downcase,
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
    masked_data[7] = "#{masked_data[7].split("@").first}@***" if masked_data[7].include?("@")
    puts "✅ Adding event: #{masked_data[0]} by #{masked_data[6]} at #{masked_data[3]}"

    begin
      # Add to Google Sheets
      settings.google_sheets.append_row(
        settings.spreadsheet_id,
        settings.events_range,
        event_data
      )

      puts "✅ Event successfully added to spreadsheet"

      # Respond with JSON status
      content_type :json
      {
        status: "ok",
        message: "Event added successfully",
        event_name: validated_params[:name],
        event_date: start_str
      }.to_json
    rescue => e
      puts "❌ Error adding event: #{e.message}"
      puts "   Backtrace: #{e.backtrace.first(3).join(" | ")}"
      content_type :json
      status 500
      {
        status: "error",
        message: "Failed to add event. Please try again."
      }.to_json
    end
  else
    # Validation failed: return errors as JSON
    content_type :json
    status 422
    {
      status: "error",
      message: "Validation failed",
      errors: result.errors.to_h
    }.to_json
  end
end
