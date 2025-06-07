# Mock Liquid to avoid dependency issues in tests
module Liquid
  class Template
    def self.register_filter(filter_module)
    end
  end
end
