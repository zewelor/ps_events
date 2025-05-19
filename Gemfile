source "https://rubygems.org"
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

gem "zeitwerk"
gem "amazing_print"
gem "icalendar"
gem "csv"

group :development, :test do
  gem "debug", platforms: %i[mri mingw x64_mingw]
  gem "irb"
end

group :development do
  gem "standard"
  gem "lefthook"
  gem "ruby-lsp", require: false
end

group :test do
  gem "simplecov", require: false
end

group :jekyll_plugins do
  gem "jekyll-datapage-generator"
  gem "jekyll-sitemap", "~> 1.4"
  gem "jekyll-tailwindcss"
end

gem "tzinfo", "~> 2.0"
gem "tzinfo-data", "~> 1.2025"

gem "jekyll", "~> 4.4"

gem "bigdecimal", "~> 3.1"
