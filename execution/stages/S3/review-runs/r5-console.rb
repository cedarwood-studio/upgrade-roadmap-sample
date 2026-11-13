# frozen_string_literal: true

# Fifth review, S3. Starts the Rails console on a pseudo terminal, the way an
# operator meets it, and prints what it shows: the banner and the prompt.
#   ruby /out/r5-console.rb
require "pty"
require "timeout"
out = +""
PTY.spawn({ "RAILS_ENVIRONMENT" => "production", "TERM" => "dumb" }, "bin/rails", "console") do |r, w, pid|
  reader = Thread.new do
    loop { out << r.readpartial(4096) }
  rescue StandardError
    nil
  end
  sleep 12
  w.puts "1 + 1"
  sleep 2
  w.puts "exit"
  begin
    Timeout.timeout(10) { Process.wait(pid) }
  rescue StandardError
    nil
  end
  reader.join(1)
end
clean = out.gsub(/\e\[[0-9;?]*[A-Za-z]/, "").delete("\r")
puts clean.lines.reject { |l| l =~ /^No configuration|^Only using|^No secret key/ }.map { |l| l.rstrip[0, 200] }.uniq.first(14)
