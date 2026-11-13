# frozen_string_literal: true

# Fifth review, S3. What the application hands to Sentry, which no earlier review
# compared. Boots with a DSN, swaps the transport for one that keeps events in
# memory, then sends requests that end in an unhandled error, a missing record
# and a malformed body through the whole production stack.
#   LOGGING_SENTRY_DSN=http://k@127.0.0.1:9/1 bundle exec ruby /out/r5-sentry.rb
require "rack"
require "rack/mock"
built = Rack::Builder.parse_file(File.expand_path("config.ru", Dir.pwd))
app = built.is_a?(Array) ? built.first : built
transport = Sentry::DummyTransport.new(Sentry.configuration)
Sentry.get_current_client.instance_variable_set(:@transport, transport)
ApplicationController.class_eval do
  def process_action(*)
    raise "r5 boom" if request.get_header("HTTP_X_R5_BOOM")
    raise ActiveRecord::RecordNotFound, "r5 missing" if request.get_header("HTTP_X_R5_MISSING")

    super
  end
end
host = Postal::Config.postal.web_hostname
[["GET", "/login", { "HTTP_X_R5_BOOM" => "1" }], ["HEAD", "/login", { "HTTP_X_R5_BOOM" => "1" }], ["GET", "/login", { "HTTP_X_R5_MISSING" => "1" }],
 ["POST", "/api/v1/send/message", { "CONTENT_TYPE" => "application/json", :input => "{not json" }], ["GET", "/no/such/page", {}],
 ["GET", "/login", {}]].each do |verb, path, extra|
  res = Rack::MockRequest.new(app).request(verb, path, { "HTTP_HOST" => host }.merge(extra))
  puts "#{verb} #{path} #{extra.keys.grep(/R5/).join} -> #{res.status}"
end
sleep 2
Sentry.get_current_client.flush rescue nil
events = transport.events
puts "sentry events: #{events.size}"
events.each do |event|
  h = event.to_hash
  values = Array(h.dig(:exception, :values))
  puts "event type=#{h[:type].inspect} level=#{h[:level]} transaction=#{h[:transaction].inspect} " \
       "exceptions=#{values.map { |v| "#{v[:type]}(#{v[:value].to_s[0, 40]}) handled=#{v.dig(:mechanism, :handled).inspect} mech=#{v.dig(:mechanism, :type).inspect}" }.join(' <- ')} " \
       "tags=#{h[:tags].inspect} request=#{h.dig(:request, :method)} #{h.dig(:request, :url)}"
end
puts "envelopes: #{transport.envelopes.size} #{transport.envelopes.map { |e| e.items.map { |i| i.headers[:type] }.join('+') }.tally.inspect}"
