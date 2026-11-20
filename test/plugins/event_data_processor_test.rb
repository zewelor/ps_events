require "minitest/autorun"
require "open3"

class EventDataProcessorTest < Minitest::Test
  def test_required_configuration_and_event_fields_fail_clearly
    program = <<~RUBY
      require "jekyll"
      require_relative "events_listing/_plugins/event_data_processor"

      config = {"url" => "https://example.test", "page_gen" => [{"data" => "events", "dir" => "events"}]}
      event = {"name" => "Concert", "start_date" => "01/12/2025"}
      case ARGV.fetch(0)
      when "page_gen" then config.delete("page_gen")
      when "events" then config["page_gen"] = []
      when "dir" then config["page_gen"][0].delete("dir")
      else event.delete(ARGV.fetch(0))
      end
      site = Struct.new(:config, :data).new(config, {"events" => [event]})
      Jekyll::Hooks.trigger(:site, :post_read, site)
    RUBY

    %w[page_gen events dir name start_date].each do |missing|
      _stdout, stderr, status = Open3.capture3("bundle", "exec", "ruby", "-e", program, missing)
      refute status.success?, missing
      assert_match(/KeyError.*#{missing}|#{missing}.*KeyError/m, stderr, missing)
    end
  end
end
