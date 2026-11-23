require "minitest/autorun"
require "open3"
require "tmpdir"

class ConvertImageCliTest < Minitest::Test
  def test_removes_processed_image_when_local_copy_fails
    Dir.mktmpdir("convert-image-test-") do |dir|
      processed_path = File.join(dir, "processed.webp")
      preload = File.join(dir, "preload.rb")
      File.write(preload, <<~RUBY)
        require #{File.expand_path("../../lib/server/image_service", __dir__).inspect}
        class ImageService
          def self.validate_and_process(uploaded_file)
            uploaded_file.fetch(:tempfile).close
            File.write(ENV.fetch("CONVERT_TEST_PROCESSED_PATH"), "processed")
            ENV.fetch("CONVERT_TEST_PROCESSED_PATH")
          end
        end
        module CopyFailure
          def cp(*)
            raise IOError, "local copy failed"
          end
        end
        FileUtils.singleton_class.prepend(CopyFailure)
      RUBY

      env = {"CONVERT_TEST_PROCESSED_PATH" => processed_path, "GH_TOKEN" => nil, "GH_REPO" => nil}
      stdout, stderr, status = Open3.capture3(env,
        "bundle", "exec", "ruby", "-r", preload,
        File.expand_path("../../bin/convert_image", __dir__),
        File.expand_path("../fixtures/ocr_events.png", __dir__))

      refute status.success?, stderr
      assert_includes stdout, "Error: local copy failed"
      refute File.exist?(processed_path), "Processed image should be removed after copy failure"
    end
  end
end
