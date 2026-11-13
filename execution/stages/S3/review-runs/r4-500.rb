# frozen_string_literal: true

# Fourth review, S3. The 500 page, which the notes say was read and not measured.
# Makes the login action raise when a marker header is present, then sends GET
# and HEAD through the whole production stack and prints what comes back.
#   bundle exec ruby /out/r4-500.rb
require "rack"
require "rack/mock"
built = Rack::Builder.parse_file(File.expand_path("config.ru", Dir.pwd))
app = built.is_a?(Array) ? built.first : built
# The first try prepended a module to SessionsController#new and the page still
# answered 200, so that hook did not take. This one sits in front of every action.
ApplicationController.class_eval do
  def process_action(*)
    raise "r4 boom" if request.get_header("HTTP_X_R4_BOOM")

    super
  end
end
host = Postal::Config.postal.web_hostname
[
  ["GET", {}], ["HEAD", {}],
  ["GET", { "HTTP_ACCEPT" => "*/*" }], ["HEAD", { "HTTP_ACCEPT" => "*/*" }],
  ["GET", { "HTTP_ACCEPT" => "text/html,application/xhtml+xml" }], ["HEAD", { "HTTP_ACCEPT" => "text/html,application/xhtml+xml" }],
  ["GET", { "HTTP_ACCEPT" => "application/json" }], ["HEAD", { "HTTP_ACCEPT" => "application/json" }]
].each do |verb, extra|
  res = Rack::MockRequest.new(app).request(verb, "/login", { "HTTP_HOST" => host, "HTTP_X_R4_BOOM" => "1" }.merge(extra))
  h = res.headers.to_h.transform_keys { |k| k.to_s.downcase }
  puts format("%-4s accept=%-32s -> %s content-type=%s content-length=%s body=%db", verb, extra["HTTP_ACCEPT"].inspect, res.status,
              h["content-type"].inspect, h["content-length"].inspect, res.body.to_s.bytesize)
end
