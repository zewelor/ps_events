# frozen_string_literal: true

# AuthRegistry - central registry for authentication methods
# Allows registering multiple authentication strategies that are tried in order
module AuthRegistry
  extend self

  def register(name, handler)
    @handlers ||= {}
    @handlers[name] = handler
  end

  def available_methods
    @handlers&.keys || []
  end

  def authenticate(request)
    if @handlers.nil? || @handlers.empty?
      return {authenticated: false, error: "No authentication methods configured"}
    end

    @handlers.each do |name, handler|
      result = handler.call(request)
      return result.merge(method: name) if result[:authenticated]
    end

    {authenticated: false, error: "Authentication failed"}
  end
end
