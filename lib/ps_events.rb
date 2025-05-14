# frozen_string_literal: true

Bundler.require(:default)

# https://github.com/fxn/zeitwerk#synopsis
loader = Zeitwerk::Loader.for_gem
loader.setup # ready!

begin
  require "dotenv/load"
# rubocop:disable Lint/SuppressedException
rescue LoadError
end
# rubocop:enable Lint/SuppressedException

module PsEvents
  class Error < StandardError; end
  # Your code goes here...
end
