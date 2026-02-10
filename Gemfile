source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

gem "zeitwerk"
# Manually require this gem to avoid issues with autoloading and some args auto parsing
# --name is a Minitest flag. Something in your app is require-ing sinatra during test boot, and Sinatra (via Rack) is trying to parse ARGV as if it were launching a server. When Rack’s OptionParser sees --name, it blows up → invalid option: --name. That’s why Bundler reports the failure while “trying to load the gem 'sinatra'”.
gem "sinatra", require: false
gem "dry-validation", "~> 1.11"
gem "json-schema", "~> 6.0"
gem "activesupport", "~> 8.0"

group :development, :test do
  gem "debug", platforms: %i[mri]
  gem "irb"
  gem "rack-test", "~> 2.2"
  gem "minitest", "~> 5.25"
end

group :development do
  gem "standard"
  gem "lefthook"
  gem "ruby-lsp", require: false
  gem "amazing_print"

  gem "icalendar"
  gem "csv"

  gem "tzinfo", "~> 2.0"
  gem "tzinfo-data", "~> 1.2025"

  gem "jekyll", "~> 4.4"

  gem "bigdecimal", "~> 4.0"
end

group :test do
  gem "simplecov", require: false
  gem "webmock", "~> 3.23"
end

group :jekyll_plugins do
  gem "jekyll-datapage-generator", github: "avillafiorita/jekyll-datapage_gen"
  gem "jekyll-sitemap", "~> 1.4"
  gem "jekyll-tailwindcss"
  gem "jekyll-environment-variables"
  gem "jekyll-seo-tag", github: "jekyll/jekyll-seo-tag"
end

gem "rackup", "~> 2.2"
gem "puma", "~> 7.0"

gem "google-apis-sheets_v4", "~> 0.46.0"
gem "retryable", "~> 3.0"

# Image processing gem
gem "mini_magick", "~> 5.2"

gem "ruby_llm", "~> 1.9"
