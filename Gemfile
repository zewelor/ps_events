source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

gem "zeitwerk"
gem "sinatra"
gem "dotenv"
gem "dry-validation", "~> 1.11"

group :development, :test do
  gem "debug", platforms: %i[mri mingw x64_mingw]
  gem "irb"
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

  gem "bigdecimal", "~> 3.1"
  gem "rerun"
end

group :jekyll_plugins do
  gem "jekyll-datapage-generator"
  gem "jekyll-sitemap", "~> 1.4"
  gem "jekyll-tailwindcss"
  gem "jekyll-environment-variables"
  gem "jekyll-seo-tag"
end

gem "rackup", "~> 2.2"
gem "puma", "~> 6.6"

gem "google-apis-sheets_v4", "~> 0.44.0"
gem "jwt", "~> 2.10"

# Image processing gem
gem "mini_magick", "~> 5.2"
