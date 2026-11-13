# frozen_string_literal: true

# Third review, S3. Prints status and headers for a few requests to the running
# puma process, with the Accept headers common clients send.
require "net/http"

host = ENV.fetch("POSTAL_WEB_HOSTNAME", "postal.example.com")
SKIP = %w[x-request-id x-runtime date etag set-cookie server-timing].freeze
[
  ["HEAD", "/no/such/page", "*/*"],
  ["HEAD", "/no/such/page", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"],
  ["HEAD", "/no/such/page", nil],
  ["GET", "/no/such/page", "*/*"],
  ["HEAD", "/login", "*/*"],
  ["HEAD", "/assets/nonexistent.css", "*/*"],
  ["HEAD", "/no/such/page.json", "*/*"]
].each do |verb, path, accept|
  begin
    http = Net::HTTP.new("127.0.0.1", 5055)
    http.open_timeout = 3
    http.read_timeout = 8
    req = Net::HTTPGenericRequest.new(verb, false, verb != "HEAD", path)
    req["Host"] = host
    req["Accept"] = accept if accept
    req.delete("Accept") unless accept
    res = http.request(req)
    headers = res.each_header.reject { |k, _| SKIP.include?(k) }.sort.map { |k, v| "#{k}=#{v}" }.join("; ")
    puts "#{verb} #{path} Accept=#{accept.inspect} -> #{res.code} | #{headers} | body #{res.body.to_s.bytesize}b"
  rescue StandardError => e
    puts "#{verb} #{path} Accept=#{accept.inspect} -> #{e.class}: #{e.message[0, 120]}"
  end
end
