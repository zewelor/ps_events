require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/test_*.rb"]
end

task default: :test

# Add a task to run specific test files
desc "Run datetime helpers tests"
task :test_datetime do
  ruby "test/test_datetime_helpers.rb"
end

# Add a task to run tests with coverage (if simplecov is being used)
desc "Run tests with coverage"
task :test_coverage do
  ENV["COVERAGE"] = "true"
  Rake::Task[:test].invoke
end
