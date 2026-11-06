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
require_relative "../lib/server/auth_guard"
require_relative "../lib/server/param_utils"

EVENT_ANALYSIS_LLM_TIMEOUT = 300

set :bind, "0.0.0.0"
set :port, ENV["PORT"] || 4567

# Helper methods for JSON responses
helpers do
  def json_response(data, status_code = 200)
    content_type :json
    status status_code
    data.to_json
  end

  def json_error(message, status_code = 422, errors = nil, error_code: nil)
    response_data = {
      status: "error",
      message: message
    }
    response_data[:error_code] = error_code if error_code
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
      GitHubService.ensure_image(image_path)
      puts "✅ Image available on GitHub (production)"
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

  # Share development behavior and failure responses while retaining each route's authentication strategy.
  def authenticate_user!(missing_message: "Google authentication required")
    if settings.environment == :development
      return {authenticated: true, email: "development@example.com", method: :development}
    end

    result = if block_given?
      yield
    else
      AuthGuard.authenticate_google_token(ParamUtils.fetch(params, :google_token), missing_message: missing_message)
    end
    unless result[:authenticated]
      error = result[:error] || "Authentication required"
      status_code = result[:status_code] || 401
      puts "❌ #{error}"
      halt status_code, json_error(error, status_code)
    end

    puts "✅ Authenticated via #{result[:method] || :google_oauth}: #{result[:email]}"
    result
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

  def distinct_event_references
    value = ParamUtils.fetch(params, :distinct_from)
    return [] if value.nil?

    references = JSON.parse(value)
    unless references.is_a?(Array) && references.all? { |reference| reference.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(reference) }
      raise ArgumentError, "Invalid distinct_from"
    end
    references
  end

  def ingestion_response(results, events: nil, event: nil, failed: false, image_ref: nil)
    counts = {
      added: results.count { |result| result[:status] == "added" },
      skipped: results.count { |result| result[:status] == "skipped" },
      conflicted: results.count { |result| result[:status] == "conflict" }
    }
    summary = "Adicionados: #{counts[:added]}. Já existentes: #{counts[:skipped]}. A aguardar revisão: #{counts[:conflicted]}."
    message = if failed
      "Não foi possível concluir a submissão. #{summary} Os dados foram mantidos. Verifique os eventos antes de tentar novamente."
    elsif counts[:conflicted].positive?
      "Encontrámos eventos semelhantes. Confirme se são os mesmos eventos."
    elsif counts[:added].zero? && counts[:skipped].positive?
      if counts[:skipped] == 1
        "Este evento já se encontra registado. Não precisa de o submeter novamente."
      else
        "Os #{counts[:skipped]} eventos já se encontram registados. Não precisa de os submeter novamente."
      end
    else
      summary
    end
    data = {message: message, counts: counts, results: results}
    data[:image_ref] = image_ref if image_ref
    data[:events] = events if events
    if event
      data[:event_name] = event[:name]
      data[:event_date] = event[:start_date]
    end
    if failed
      json_response(data.merge(status: "error", error_code: "ingestion_failed"), 503)
    elsif counts[:conflicted].positive?
      json_response(data.merge(status: "needs_review"), 409)
    else
      outcome = (counts[:added].zero? && counts[:skipped].positive?) ? "skipped" : "added"
      json_success(message, data.merge(outcome: outcome))
    end
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

configure do
  next if ENV["APP_ENV"] == "test"

  code_version = ENV.fetch("GIT_CODE_VERSION", "unknown").to_s
  puts "ℹ️ GIT_CODE_VERSION=#{code_version}"
end

# Register authentication methods
configure do
  # Google OAuth - always available
  AuthRegistry.register(:google_oauth, lambda do |request|
    params = request.params
    google_token = ParamUtils.fetch(params, :google_token)
    # No token: silent miss so another strategy (e.g. API Bearer) can try.
    return {authenticated: false} if google_token.nil? || google_token.strip.empty?

    AuthGuard.authenticate_google_token(google_token)
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
  authenticate_user!

  begin
    image_path = process_event_image(params[:event_image])
    json_success("Image uploaded", {filename: File.basename(image_path, ".*")})
  rescue => e
    json_error(e.message)
  end
end

post "/events_ocr" do
  # Authentication via AuthRegistry (supports Google OAuth or API Bearer)
  auth = authenticate_user! { AuthRegistry.authenticate(request) }
  user_email = auth[:email]
  # Bearer callers can retry explicit pre-save failures with bounded backoff. Limit
  # each model request to 300 seconds and disable model and validation retries to
  # avoid multiplying attempts and reduce the risk of exceeding the caller's timeout.
  # Google requests retain their defaults. The timeout does not bound the whole upload.
  # The authentication method selects this policy; it does not identify the operator.
  api_bearer = auth[:method] == :api_bearer

  begin
    use_image = params[:use_event_image]
    additional_text = params[:event_text].to_s.strip.presence
    if additional_text&.length.to_i > EventOcrService::ADDITIONAL_TEXT_MAX_LENGTH
      return json_error("As informações adicionais não podem exceder 5000 caracteres")
    end

    image_path = validate_event_image(params[:event_image])
    image_ref = File.basename(image_path, ".webp") if use_image && !image_path.empty?
    begin
      options = {retry_sleep: 5, additional_text: additional_text}
      if api_bearer
        options[:llm_recovery] = :none
        options[:request_timeout] = EVENT_ANALYSIS_LLM_TIMEOUT
      end
      events = EventOcrService.call(image_path, **options)
    rescue RubyLLM::RateLimitError => e
      puts "⚠️ Rate limit / quota exceeded in OCR: #{e.message}"
      return json_response({status: "error", message: "Limite de pedidos/quota do modelo LLM excedido: #{e.message}",
                            error_code: "rate_limit_exceeded", retry_safe: true}, 429)
    rescue RubyLLM::ServiceUnavailableError, RubyLLM::OverloadedError, RubyLLM::ServerError, Faraday::TimeoutError, Faraday::ConnectionFailed => e
      raise "Erro ao analisar imagem: #{e.message}" if !api_bearer && (e.is_a?(Faraday::TimeoutError) || e.is_a?(Faraday::ConnectionFailed))

      puts "⚠️ OCR temporarily unavailable: #{e.message}"
      return json_error("O serviço de análise está temporariamente indisponível. Tente novamente mais tarde.", 503,
        error_code: "ocr_temporarily_unavailable")
    end

    ocr_submitter_email = user_email.sub("@", "+ocr@")
    service = AddEventService.new(
      google_sheets: settings.google_sheets,
      spreadsheet_id: settings.spreadsheet_id,
      events_range: settings.events_range
    )

    pp events

    raise "Invalid OCR event list" unless events.is_a?(Array) && events.all? { |event| event.is_a?(Hash) }

    results = []
    image_uploaded = false
    events.each_with_index do |ev, index|
      result = service.add_event(ev,
        submitter_email: ocr_submitter_email,
        image_path: use_image ? image_path : "") do
        if use_image && !image_uploaded
          upload_image_if_production(image_path)
          image_uploaded = true
        end
      end
      results << result.merge(index: index)
    rescue => e
      puts "❌ Error saving OCR event #{index}: #{e.message}"
      results << {status: "failed", index: index, event: ev}
      events.each_with_index do |remaining, remaining_index|
        results << {status: "not_attempted", index: remaining_index, event: remaining} if remaining_index > index
      end
      return ingestion_response(results, events: events, failed: true, image_ref: image_ref)
    end

    ingestion_response(results, events: events, image_ref: image_ref)
  rescue RubyLLM::RateLimitError => e
    puts "⚠️ Rate limit / quota exceeded in OCR: #{e.message}"
    json_error("Limite de pedidos/quota do modelo LLM excedido: #{e.message}", 429, error_code: "rate_limit_exceeded")
  rescue => e
    pp events
    puts "❌ Error processing OCR: #{e.message}"
    json_error(e.message)
  end
end

# Handle form submissions to add new event
post "/add_event" do
  puts "📝 Received event submission with params: #{params.keys}"

  google_user_email = authenticate_user!(
    missing_message: "Google authentication is required to submit an event"
  )[:email]

  # Remove the file upload from params for validation
  validation_params = params.dup
  validation_params.delete(:event_image)
  validation_params.delete(:google_token)
  validation_params.delete(:distinct_from)
  validation_params.delete(:image_ref)

  begin
    distinct_from = distinct_event_references
    image_ref = ParamUtils.fetch(params, :image_ref)
    if image_ref
      raise ArgumentError, "Image reference and file cannot be combined" if params[:event_image]

      image_path = ImageService.path_for_reference(image_ref)
    end
  rescue JSON::ParserError, ArgumentError
    return json_error("A confirmação ou referência de imagem não é válida. Verifique os dados e tente novamente.")
  end

  image_path ||= ""

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
      unless image_ref
        image_path = validate_event_image(params[:event_image])
        image_ref = File.basename(image_path, ".webp") unless image_path.empty?
      end
    rescue => e
      return json_error(e.message)
    end

    contact_email = validated_params[:contact_email]&.strip&.downcase
    if contact_email != google_user_email.downcase
      puts "ℹ️ Event submitted by #{google_user_email} for contact #{contact_email}"
    end

    begin
      saved = AddEventService.new(
        google_sheets: settings.google_sheets,
        spreadsheet_id: settings.spreadsheet_id,
        events_range: settings.events_range
      ).add_event(validated_params, submitter_email: google_user_email, image_path: image_path, distinct_from: distinct_from) do
        if settings.environment != :production && image_ref && (!File.file?(image_path) || File.symlink?(image_path))
          raise "Processed image is unavailable; upload the source again"
        end
        upload_image_if_production(image_path) unless image_path.empty?
      end

      ingestion_response([saved], event: validated_params, image_ref: image_ref)
    rescue => e
      puts "❌ Error adding event: #{e.message}"
      puts "   Backtrace: #{e.backtrace.first(3).join(" | ")}"
      ingestion_response([{status: "failed", event: validated_params}], failed: true, image_ref: image_ref)
    end
  else
    puts "❌ Validation failed: #{result.errors.to_h.inspect}"
    # Validation failed: return errors as JSON
    json_error("Validation failed\n#{result.errors.to_h.map { |k, v| "#{k}: #{v.join(", ")}" }.join("\n")}", 422)
  end
end
