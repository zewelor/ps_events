require "minitest/autorun"
require "json"
require "open3"
require "tmpdir"

class AddEventCliTest < Minitest::Test
  def test_invalid_event_is_rejected_before_services_or_image_processing
    event = {
      name: "Concerto de teste",
      start_date: "09/10/2026junk",
      location: "Largo do Pelourinho",
      description: "Concerto de teste com entrada gratuita.",
      category: "Música",
      organizer: "Organização de teste"
    }
    environment = {
      "GOOGLE_SPREADSHEET_ID" => nil,
      "EVENTS_SHEET_RANGE" => nil,
      "GOOGLE_SERVICE_ACCOUNT_JSON_BASE64" => nil
    }
    command = [
      "bundle", "exec", "ruby",
      File.expand_path("../../bin/add_event", __dir__),
      File.expand_path("../fixtures/ocr_events.png", __dir__),
      JSON.generate(event)
    ]

    stdout, stderr, status = Open3.capture3(environment, *command)

    refute status.success?
    assert_includes stderr, "invalid event"
    assert_includes stderr, "start_date"
    refute_includes stdout, "Processing image"
  end

  def test_image_is_only_published_when_event_is_added
    Dir.mktmpdir("add-event-test-") do |dir|
      processed_path = File.join(dir, "processed.webp")
      copy_marker = File.join(dir, "copied")
      preload = File.join(dir, "preload.rb")
      File.write(preload, <<~RUBY)
        require "bundler/setup"
        Bundler.require(:development)
        require #{File.expand_path("../../lib/server/sheets_config", __dir__).inspect}
        require #{File.expand_path("../../lib/server/image_service", __dir__).inspect}
        module SheetsConfig
          def self.missing_env_keys
            []
          end

          def self.add_event_service
            Object.new.tap do |service|
              def service.add_event(event, submitter_email:, image_path:)
                return {status: "conflict", candidates: []} if ENV.fetch("ADD_TEST_STATUS") == "conflict"
                yield
                {status: "added", range: "Events!A2:S2"}
              end
            end
          end
        end

        class ImageService
          def self.validate_and_process(uploaded_file)
            uploaded_file.fetch(:tempfile).close
            File.write(ENV.fetch("ADD_TEST_PROCESSED_PATH"), "processed")
            ENV.fetch("ADD_TEST_PROCESSED_PATH")
          end
        end

        module CopyRecorder
          def cp(source, destination)
            File.write(ENV.fetch("ADD_TEST_COPY_MARKER"), source)
          end
        end
        FileUtils.singleton_class.prepend(CopyRecorder)
      RUBY
      event = {name: "Concerto de teste", start_date: "09/10/2026",
               description: "Concerto de teste com entrada gratuita.", category: "Música"}
      env = {"ADD_TEST_PROCESSED_PATH" => processed_path, "ADD_TEST_COPY_MARKER" => copy_marker,
             "GH_TOKEN" => nil, "GH_REPO" => nil}
      command = ["bundle", "exec", "ruby", "-r", preload, File.expand_path("../../bin/add_event", __dir__),
        File.expand_path("../fixtures/ocr_events.png", __dir__), JSON.generate(event)]

      stdout, stderr, status = Open3.capture3(env.merge("ADD_TEST_STATUS" => "conflict"), *command)
      assert_equal 2, status.exitstatus, stderr
      assert_includes stdout, '"status": "conflict"'
      refute File.exist?(copy_marker), "A conflict must not publish the image"
      refute File.exist?(processed_path), "A conflict must clean up the processed image"

      stdout, stderr, status = Open3.capture3(env.merge("ADD_TEST_STATUS" => "added"), *command)
      assert status.success?, stderr
      assert_includes stdout, "Success! Event successfully added."
      assert_equal processed_path, File.read(copy_marker)
      refute File.exist?(processed_path), "An added event must clean up the processed image"
    end
  end
end
