#!/usr/bin/env ruby
# frozen_string_literal: true

require "securerandom"

def prompt(message)
  $stdout.write(message)
  $stdout.flush
  $stdin.gets&.strip
end

email = prompt("Email do submitter (obrigatorio): ")
if email.nil? || email.empty?
  warn "Email vazio - a usar placeholder EMAIL_TODO@example.com"
  email = "EMAIL_TODO@example.com"
end

token = SecureRandom.hex(32)
pair = "#{token}:#{email}"

puts "\nChave gerada:"
puts "API_KEYS=#{pair}"

existing = ENV["API_KEYS"]
if existing && !existing.strip.empty?
  puts "\nPara adicionar ao valor existente:"
  puts "API_KEYS=#{existing},#{pair}"
end

puts "\nGuarda este token em local seguro."
