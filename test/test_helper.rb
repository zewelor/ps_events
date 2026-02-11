require "webmock/minitest"

# Minitest 6 removed Object#stub — restore it for test mocking
class Object
  def stub(name, val_or_callable, *block_args, **block_kwargs, &block)
    new_name = :"__minitest_stub__#{name}"
    metaclass = (class << self; self; end)

    if respond_to?(name) && !methods.include?(name)
      metaclass.send(:define_method, name) { |*a, **kw, &b| super(*a, **kw, &b) }
    end

    metaclass.send(:alias_method, new_name, name)
    metaclass.send(:define_method, name) do |*a, **kw, &b|
      if val_or_callable.respond_to?(:call)
        val_or_callable.call(*a, **kw, &b)
      else
        val_or_callable
      end
    end

    block.call(*block_args, **block_kwargs)
  ensure
    metaclass.send(:undef_method, name)
    metaclass.send(:alias_method, name, new_name)
    metaclass.send(:undef_method, new_name)
  end
end

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
