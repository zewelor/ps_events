#!/usr/bin/env ruby

require "bundler/setup"

Bundler.require(:default)

# Handle form submissions to add new event
post "/add_event" do
  # Path to events CSV data file
  data_file = File.expand_path("events_listing/_data/events.csv", __dir__)

  # Format start and end times
  start_dt = DateTime.parse(params["start_date"])
  start_str = start_dt.strftime("%d/%m/%Y %H:%M")
  end_str = if params["end_date"] && !params["end_date"].strip.empty?
    DateTime.parse(params["end_date"]).strftime("%d/%m/%Y %H:%M")
  else
    ""
  end

  # Append new event row to CSV
  CSV.open(data_file, "ab") do |csv|
    csv << [
      params["name"],
      start_str,
      end_str,
      params["location"],
      params["description"],
      params["category"],
      params["organizer"],
      params["contact_email"],
      params["contact_tel"],
      params["price"],
      params["event_link1"],
      params["event_link2"],
      params["event_link3"],
      params["event_link4"],
      "" # image placeholder
    ]
  end

  # Redirect back to home page after submission
  redirect "/", 303
end
