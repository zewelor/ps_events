ENV["APP_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "securerandom"
require "digest"
require_relative "../test_helper"
require_relative "../../bin/server"
require_relative "../fixtures/memory_sheets"

class SharedFlyerReviewTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    TestHelper.setup_network_blocking
    @previous_env = ENV.to_h.slice("GH_TOKEN", "GH_REPO")
    ENV["GH_TOKEN"] = "fixture-token"
    ENV["GH_REPO"] = "fixture/images"
    @original_settings = [app.settings.environment, app.settings.google_sheets, app.settings.events_range]
    app.set :environment, :production
    app.set :google_sheets, MemorySheets.new
    app.set :events_range, "Events!A:S"
    header "Host", "pxopulse.com"
    @image_ref = SecureRandom.uuid
    @path = File.join(ImageService::UPLOAD_DIR, "#{@image_ref}.webp")
    @bytes = "processed flyer fixture".b
    File.binwrite(@path, @bytes)
    @converted = 0
    @published = 0
    @url = "https://api.github.com/repos/fixture/images/contents/#{URI.encode_www_form_component("events_listing/assets/images/#{@image_ref}.webp")}"
    stub_request(:get, @url).with(query: {ref: "main"}).to_return do
      @published.zero? ? {status: 404} : {status: 200, body: JSON.generate(type: "file", path: "events_listing/assets/images/#{@image_ref}.webp", sha: Digest::SHA1.hexdigest("blob #{@bytes.bytesize}\0#{@bytes}"))}
    end
    stub_request(:put, @url).to_return do
      @published += 1
      {status: 201}
    end
  end

  def teardown
    app.set :environment, @original_settings[0]
    app.set :google_sheets, @original_settings[1]
    app.set :events_range, @original_settings[2]
    header "Host", nil
    File.delete(@path) if File.exist?(@path)
    %w[GH_TOKEN GH_REPO].each { |key| @previous_env.key?(key) ? ENV[key] = @previous_env[key] : ENV.delete(key) }
    TestHelper.reset_network_mocks
  end

  def event(day = "21", name = "Concerto")
    {name: name, start_date: "#{day}/11/2026", location: "Centro Cultural", description: "Concerto com entrada gratuita.", category: "Música", organizer: "Associação Cultural"}
  end

  def seed_existing(input)
    fields = EventDuplicateCheck::FIELD_COLUMNS.invert
    app.settings.google_sheets.approved_rows << MemorySheets::HEADERS.map { |header| input[fields[header]].to_s }
  end

  def submit_ocr(events, use_image: true)
    capture_io do
      AuthRegistry.stub :authenticate, {authenticated: true, email: SecurityService::WHITELISTED_EMAILS.first, method: :google_oauth} do
        EventOcrService.stub :call, events do
          ImageService.stub :validate_and_process, ->(*) {
            @converted += 1
            @path
          } do
            params = {event_image: Rack::Test::UploadedFile.new(__FILE__, "image/png")}
            params[:use_event_image] = "on" if use_image
            post "/events_ocr", params
          end
        end
      end
    end
    JSON.parse(last_response.body)
  end

  def submit_event(input, **metadata)
    capture_io do
      GoogleAuthService.stub :validate_token, {success: true, email: SecurityService::WHITELISTED_EMAILS.first} do
        post "/add_event", input.merge(metadata).merge(google_token: "fixture-token")
      end
    end
    JSON.parse(last_response.body)
  end

  def resolve(conflict, image_ref: @image_ref)
    submit_event(conflict.fetch("event"), image_ref: image_ref,
      distinct_from: JSON.generate(conflict.fetch("candidates").map { |candidate| candidate.fetch("fingerprint") }))
  end

  def test_all_conflict_batch_resolutions_share_one_conversion_and_publication
    seed_existing(event("21", "Registo A"))
    seed_existing(event("22", "Registo B"))
    body = submit_ocr([event("21", "Concerto A"), event("22", "Concerto B")])

    assert_equal 409, last_response.status
    assert_equal @image_ref, body["image_ref"]
    assert_equal 0, @published
    body.fetch("results").each do |conflict|
      resolved = resolve(conflict)
      assert_equal 200, last_response.status
      assert_equal "added", resolved["outcome"]
      assert_equal @image_ref, resolved["image_ref"]
    end
    assert_equal 1, @converted
    assert_equal 1, @published
    assert_equal [@image_ref, @image_ref], app.settings.google_sheets.rows.map { |row| row[14] }
  end

  def test_partial_failure_keeps_a_published_image_reusable_after_temp_expiry
    seed_existing(event("21", "Já registado"))
    app.settings.google_sheets.append_failure_after = 1
    body = submit_ocr([event("22"), event, event("23"), event("24")])

    assert_equal 503, last_response.status
    assert_equal %w[added conflict failed not_attempted], body["results"].map { |result| result["status"] }
    assert_equal @image_ref, body["image_ref"]
    File.delete(@path)
    app.settings.google_sheets.append_failure_after = nil
    resolved = resolve(body["results"][1])

    assert_equal 200, last_response.status
    assert_equal "added", resolved["outcome"]
    assert_equal 1, @converted
    assert_equal 1, @published
    assert_equal [@image_ref, @image_ref], app.settings.google_sheets.rows.map { |row| row[14] }
  end

  def test_missing_unpublished_flyer_cannot_append_a_broken_image_reference
    seed_existing(event("21", "Já registado"))
    body = submit_ocr([event])
    File.delete(@path)
    resolved = resolve(body["results"].first)

    assert_equal 503, last_response.status
    assert_equal "ingestion_failed", resolved["error_code"]
    assert_empty app.settings.google_sheets.rows
    assert_equal 0, @published
  end

  def test_skips_and_conflicts_need_no_image_lookup_even_after_temp_expiry
    seed_existing(event)
    File.delete(@path)
    skipped = submit_event(event, image_ref: @image_ref)
    assert_equal "skipped", skipped["outcome"]
    conflicted = submit_event(event.merge(name: "Outro título"), image_ref: @image_ref)

    assert_equal 409, last_response.status
    assert_equal @image_ref, conflicted["image_ref"]
    assert_not_requested :get, @url
    assert_not_requested :put, @url
    assert_empty app.settings.google_sheets.rows
  end

  def test_bad_or_ambiguous_image_references_are_rejected_before_processing
    ["../../private", "#{@image_ref}.webp"].each do |image_ref|
      submit_event(event, image_ref: image_ref)
      assert_equal 422, last_response.status
    end
    submit_event(event, image_ref: @image_ref, event_image: Rack::Test::UploadedFile.new(__FILE__, "image/png"))

    assert_equal 422, last_response.status
    assert_empty app.settings.google_sheets.rows
    assert_not_requested :put, @url
  end

  def test_disabled_flyer_does_not_offer_a_reference_or_publish_an_image
    body = submit_ocr([event], use_image: false)

    assert_equal 200, last_response.status
    refute body.key?("image_ref")
    assert_equal "", app.settings.google_sheets.rows.first[14]
    assert_equal 0, @published
  end

  def test_development_ocr_review_saves_without_unavailable_google_sign_in
    app.set :environment, :development
    header "Host", "localhost"
    seed_existing(event("21", "Já registado"))
    body = nil
    resolved = nil
    capture_io do
      AuthRegistry.stub :authenticate, ->(*) { flunk "Development must not request authentication" } do
        GoogleAuthService.stub :validate_token, ->(*) { flunk "Development must not validate a Google token" } do
          EventOcrService.stub :call, [event("20"), event] do
            ImageService.stub :validate_and_process, @path do
              post "/events_ocr", {event_image: Rack::Test::UploadedFile.new(__FILE__, "image/png"), use_event_image: "on"}
            end
          end
          assert_equal 409, last_response.status
          body = JSON.parse(last_response.body)
          conflict = body.fetch("results").find { |result| result.fetch("status") == "conflict" }
          post "/add_event", conflict.fetch("event").merge(
            "image_ref" => body.fetch("image_ref"),
            "distinct_from" => JSON.generate(conflict.fetch("candidates").map { |candidate| candidate.fetch("fingerprint") })
          )
          resolved = JSON.parse(last_response.body)
        end
      end
    end

    assert_equal 200, last_response.status
    assert_equal "added", resolved["outcome"]
    assert_equal ["development+ocr@example.com", "development@example.com"], app.settings.google_sheets.rows.map { |row| row[1] }
    assert_equal [@image_ref, @image_ref], app.settings.google_sheets.rows.map { |row| row[14] }
    assert_not_requested :get, @url
    assert_equal 0, @published
  end

  def test_production_still_requires_authentication_for_both_ingestion_routes
    registry_calls = 0
    capture_io do
      post "/add_event", event
      assert_equal 401, last_response.status
      AuthRegistry.stub :authenticate, ->(*) {
        registry_calls += 1
        {authenticated: false, error: "Authentication required", status_code: 401}
      } do
        post "/events_ocr", {}
      end
    end

    assert_equal 401, last_response.status
    assert_equal 1, registry_calls
    assert_empty app.settings.google_sheets.rows
    assert_equal 0, @published
  end
end
