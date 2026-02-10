# frozen_string_literal: true

# Small helper for dealing with Rack/Sinatra params, which can contain string
# keys even when code expects symbols.
module ParamUtils
  extend self

  def fetch(params, key)
    params[key.to_s] || params[key.to_sym]
  end
end
