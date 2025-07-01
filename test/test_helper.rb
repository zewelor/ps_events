require "webmock/minitest"

module TestHelper
  def self.setup_network_blocking
    # Block all HTTP requests to ensure tests don't make real network calls
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  def self.reset_network_mocks
    WebMock.reset!
  end

  def with_stubbed_llm
    dummy_chat = Object.new
    RubyLLM.stub(:chat, dummy_chat) { yield }
  end
end
