# frozen_string_literal: true

# After a walk: the steps where Decidim's service worker showed its stored
# copy of a page, each with the time the server took to answer the request
# of that step, read from the development application's log. The worker shows
# its copy when the answer takes more than 3 seconds.
#
#   docker compose run --rm app ruby script/walk/stored_copies.rb tmp/walk/walk.json development_app/log/development.log
#
# Prints a table in Markdown. For comparison it also gives, for every address
# that was shown from a copy, the server's times for the other requests of the
# same address during the walk.
require "json"
require "time"

rows = JSON.parse(File.read(ARGV.fetch(0)))
log = File.read(ARGV.fetch(1), encoding: "utf-8", invalid: :replace).gsub(/\e\[[0-9;]*m/, "").lines

# Every page request in the log: its address, when it started, how long the
# server took to complete it.
requests = []
log.each_with_index do |line, at|
  started = line.match(/\AStarted GET "([^"]+)" for \S+ at (\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) \+0000/)
  next unless started

  completed = log[(at + 1)..(at + 5000)].to_a.find { |later| later.match?(/\ACompleted \d+ .* in \d+ms \(Views:/) || later.start_with?("Started GET \"#{started[1]}\"") }
  took = completed.to_s[/\ACompleted \d+ .* in (\d+)ms/, 1]
  requests << { address: started[1], at: Time.parse("#{started[2]} UTC"), ms: took&.to_i }
end

first = rows.filter_map { |row| row["at"] && Time.iso8601(row["at"]) }.min
last = rows.filter_map { |row| row["at"] && Time.iso8601(row["at"]) }.max
during = requests.select { |request| request[:at].between?(first - 60, last) }
copies = rows.select { |row| row["storedCopy"] }

puts "Steps: #{rows.size}. Steps that showed the service worker's stored copy: #{copies.size}."
puts
puts "| Check | Browser | Width | Step | Address | The copy was drawn at step | Shown | Our cookie | The server answered this step's request in |"
puts "| --- | --- | --- | --- | --- | --- | --- | --- | --- |"
copies.each do |row|
  seen = Time.iso8601(row["at"])
  request = during.reverse.find { |candidate| candidate[:address] == row["address"] && candidate[:at] <= seen && candidate[:at] > seen - 90 }
  shown = row["naked"] ? "no navigation" : "full navigation"
  took = request && request[:ms] ? "#{request[:ms]} ms" : "no line found"
  cells = [row["check"], row["browser"], row["width"], row["step"], "`#{row["address"]}`", row["storedCopy"], shown, row["cookie"] ? "yes" : "no", took]
  puts "| #{cells.join(" | ")} |"
end
puts
copies.map { |row| row["address"] }.uniq.each do |address|
  times = during.select { |request| request[:address] == address && request[:ms] }.map { |request| request[:ms] }.sort
  puts "`#{address}`: #{times.size} requests during the walk, the server's times in ms: #{times.join(", ")}"
end
times = during.filter_map { |request| request[:ms] }.sort
over = times.count { |ms| ms > 3000 }
puts
puts "All page requests the server completed during the walk: #{times.size}; over 3,000 ms: #{over}; " \
     "median #{times[times.size / 2]} ms, slowest #{times.last} ms."
