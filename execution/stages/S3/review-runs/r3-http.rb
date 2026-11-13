# frozen_string_literal: true

# Third review, S3. Loads config.ru the way a Rack server does and sends a fixed
# set of requests through the whole middleware stack, in whatever environment
# RAILS_ENVIRONMENT names. Writes one normalized file per request under the
# directory given as the first argument, so two versions can be compared with diff.
#   bundle exec ruby /out/r3-http.rb /tmp/s3 > /tmp/s3.log 2>&1

require "fileutils"
require "digest"
out_dir = ARGV[0] || "/tmp/r3-http"
FileUtils.mkdir_p(out_dir)

require "rack"
require "rack/mock"
built = Rack::Builder.parse_file(File.expand_path("config.ru", Dir.pwd))
app = built.is_a?(Array) ? built.first : built

deprecations = []
ActiveSupport::Notifications.subscribe("deprecation.rails") do |*, payload|
  deprecations << payload[:message].to_s.lines.first.to_s.strip[0, 200]
end

host = Postal::Config.postal.web_hostname
VOLATILE = %w[x-request-id x-runtime date etag set-cookie content-length server-timing].freeze

requests = [
  ["GET", "/login", {}],
  ["HEAD", "/login", {}],
  ["GET", "/", {}],
  ["GET", "/no/such/page", {}],
  ["HEAD", "/no/such/page", {}],
  ["FOO", "/login", {}],
  ["OPTIONS", "/login", {}],
  ["POST", "/login", { params: { email_address: "nobody@example.com", password: "nope" } }],
  ["POST", "/persist", {}],
  ["GET", "/login?a[]=1&a[b]=2", {}],
  ["GET", "/login?x=%E0%A4%A", {}],
  ["GET", "/login", { "HTTP_HOST" => "evil.example.org" }],
  ["GET", "/login.json", {}],
  ["GET", "/login", { "HTTP_ACCEPT" => "application/vnd.bogus" }],
  ["GET", "/login", { "HTTP_COOKIE" => "_postal_session=garbage--bad; browser_id=x; user_session=y" }],
  ["POST", "/login", { "CONTENT_TYPE" => "multipart/form-data; boundary=x", input: "garbage" }],
  ["POST", "/api/v1/send/message", { "CONTENT_TYPE" => "application/json", input: "{bad json" }],
  ["POST", "/api/v1/send/message", { "CONTENT_TYPE" => "application/json", input: "{}" }],
  ["GET", "/api/v1/messages/message", {}],
  ["DELETE", "/api/v1/send/message", {}],
  ["GET", "/.well-known/jwks.json", {}],
  ["GET", "/assets/nonexistent.css", {}],
  ["GET", "/login/reset/nosuchtoken", {}],
  ["GET", "/anything", { "HTTP_X_POSTAL_TRACK_HOST" => "1" }],
  ["GET", "/img/abc/def", { "HTTP_X_POSTAL_TRACK_HOST" => "1" }],
  ["GET", "/abc/def", { "HTTP_X_POSTAL_TRACK_HOST" => "1" }]
]

mock = Rack::MockRequest.new(app)
summary = []
requests.each_with_index do |(verb, path, opts), i|
  opts = { "HTTP_HOST" => host }.merge(opts)
  label = format("%02d %s %s", i, verb, path)
  begin
    res = mock.request(verb, path, opts)
    headers = res.headers.to_h.transform_keys { |k| k.to_s.downcase }
    body = res.body.to_s.dup.force_encoding("UTF-8").scrub("?")
    body = body.gsub(/(authenticity_token" value=")[^"]+/, '\1X')
               .gsub(/(csrf-token" content=")[^"]+/, '\1X')
               .gsub(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/, "UUID")
    kept = headers.reject { |k, _| VOLATILE.include?(k) }.sort.map { |k, v| "#{k}: #{v}" }
    cookies = Array(headers["set-cookie"]).join("\n").split(/\n/).map { |c| c[/\A[^=]+/] }.compact.sort
    text = ["#{label} #{opts.reject { |k, _| k == 'HTTP_HOST' }.keys.join(',')}", "status: #{res.status}", *kept,
            "cookies: #{cookies.join(',')}", "body-bytes: #{body.bytesize}", "", body].join("\n")
    summary << "#{label} -> #{res.status} #{headers['content-type']} #{body.bytesize}b"
  rescue Exception => e # rubocop:disable Lint/RescueException
    text = "#{label}\nRAISED #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 300]}\n"
    summary << "#{label} -> RAISED #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 160]}"
  end
  File.write(File.join(out_dir, format("%02d.txt", i)), text)
end

File.write(File.join(out_dir, "summary.txt"), summary.join("\n") + "\n")
File.write(File.join(out_dir, "meta.txt"),
           "rails #{Rails.version} env #{Rails.env} show_exceptions=#{Rails.application.config.action_dispatch.show_exceptions.inspect} " \
           "deprecations=#{deprecations.uniq.size}\n#{deprecations.uniq.join("\n")}\n")
