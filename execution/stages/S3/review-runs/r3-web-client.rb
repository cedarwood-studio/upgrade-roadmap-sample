# frozen_string_literal: true

# Third review, S3. Real HTTP requests to the running puma process on loopback.
require "net/http"

host = ENV.fetch("POSTAL_WEB_HOSTNAME", "postal.example.com")
[
  [Net::HTTP::Get, "/login"],
  [Net::HTTP::Head, "/no/such/page"],
  [Net::HTTP::Get, "/no/such/page"],
  [Net::HTTP::Post, "/api/v1/send/message"],
  [Net::HTTP::Get, "/.well-known/jwks.json"]
].each do |klass, path|
  begin
    http = Net::HTTP.new("127.0.0.1", 5055)
    http.open_timeout = 3
    http.read_timeout = 8
    req = klass.new(path)
    req["Host"] = host
    if klass == Net::HTTP::Post
      req["Content-Type"] = "application/json"
      req.body = "{}"
    end
    res = http.request(req)
    puts "#{klass.name.split('::').last.upcase} #{path} -> #{res.code} #{res['content-type']} #{res.body.to_s.bytesize}b"
  rescue StandardError => e
    puts "#{klass.name.split('::').last.upcase} #{path} -> #{e.class}: #{e.message[0, 120]}"
  end
end
