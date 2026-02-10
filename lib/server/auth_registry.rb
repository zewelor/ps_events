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

    best_failure = nil
    @handlers.each do |name, handler|
      result = handler.call(request)
      return result.merge(method: name) if result[:authenticated]

      # Preserve actionable failures (e.g. 403 not whitelisted, 401 invalid token)
      # but keep trying other methods in case another strategy succeeds.
      if (result[:error] || result[:status_code]) && best_failure.nil?
        best_failure = result.merge(method: name)
      end
    end

    # If no handler provided an actionable failure, assume credentials were not provided at all.
    best_failure || {authenticated: false, error: "Authentication required"}
  end
end
