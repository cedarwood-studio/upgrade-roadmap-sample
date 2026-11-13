# frozen_string_literal: true

# Fourth review, S3. Run in production with a fixed secret key and the Rails log
# on, once on each version, against the same database:
#   bundle exec ruby /out/r4-app.rb <out_dir> [<cookie jar written by the other version>]
# It logs in through the real login form (forgery protection is on in production,
# which the recorded requests never exercise), walks signed-in pages and error
# paths, renders every mail, dumps the schema, and writes one normalized file
# per item so two versions can be compared with diff. With a second argument it
# also replays the other version's cookies.

require "fileutils"
require "json"
out_dir = ARGV[0] || "/tmp/r4"
other_jar = ARGV[1]
FileUtils.mkdir_p(out_dir)

require "rack"
require "rack/mock"
built = Rack::Builder.parse_file(File.expand_path("config.ru", Dir.pwd))
APP = built.is_a?(Array) ? built.first : built
HOST = Postal::Config.postal.web_hostname

deprecations = []
ActiveSupport::Notifications.subscribe("deprecation.rails") { |*, payload| deprecations << payload[:message].to_s[0, 200] }

user = User.find_by(email_address: "r4@example.com") ||
       User.create!(first_name: "Rfour", last_name: "Probe", email_address: "r4@example.com", password: "passw0rd-r4",
                    email_verified_at: Time.now, admin: true, time_zone: "London")
org = Organization.find_by(permalink: "r4org") || Organization.create!(name: "R4 Org", permalink: "r4org", owner: user)
org.organization_users.where(user: user).first_or_create!(admin: true, all_servers: true) if org.respond_to?(:organization_users)

VOLATILE = %w[x-request-id x-runtime date etag set-cookie content-length server-timing].freeze

class Jar
  attr_reader :cookies

  def initialize(cookies = {})
    @cookies = cookies
  end

  def header
    @cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
  end

  def absorb(headers)
    Array(headers["set-cookie"]).join("\n").split("\n").each do |line|
      pair = line.split(";").first.to_s
      name, value = pair.split("=", 2)
      next if name.nil?

      value.to_s.empty? ? @cookies.delete(name) : @cookies[name] = value
    end
  end
end

def call(jar, verb, path, opts = {})
  env = { "HTTP_HOST" => HOST }.merge(opts)
  env["HTTP_COOKIE"] = jar.header unless jar.cookies.empty?
  res = Rack::MockRequest.new(APP).request(verb, path, env)
  headers = res.headers.to_h.transform_keys { |k| k.to_s.downcase }
  jar.absorb(headers)
  [res, headers]
end

def normalize(body)
  body.to_s.dup.force_encoding("UTF-8").scrub("?")
      .gsub(/(authenticity_token" value=")[^"]+/, '\1X')
      .gsub(/(csrf-token" content=")[^"]+/, '\1X')
      .gsub(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/, "UUID")
end

def token_from(body)
  body.to_s[/csrf-token" content="([^"]+)/, 1] || body.to_s[/authenticity_token" value="([^"]+)/, 1]
end

summary = []
index = 0
record = lambda do |label, res, headers|
  body = normalize(res.body)
  kept = headers.reject { |k, _| VOLATILE.include?(k) }.sort.map { |k, v| "#{k}: #{v}" }
  names = Array(headers["set-cookie"]).join("\n").split("\n").map { |c| c[/\A[^=]+/] }.compact.sort
  flags = Array(headers["set-cookie"]).join("\n").split("\n").map { |c| c.split(";").drop(1).map(&:strip).map(&:downcase).reject { |a| a.start_with?("expires", "max-age") }.sort.join(",") }.uniq.sort
  text = [label, "status: #{res.status}", *kept, "cookies: #{names.join(',')}", "cookie-attributes: #{flags.join(' | ')}",
          "content-length: #{headers['content-length']}", "body-bytes: #{body.bytesize}", "", body].join("\n")
  File.write(File.join(out_dir, format("%02d.txt", index)), text)
  summary << "#{format('%02d', index)} #{label} -> #{res.status} #{headers['content-type']} #{body.bytesize}b loc=#{headers['location']}"
  index += 1
end

step = lambda do |jar, verb, path, opts = {}|
  label = "#{verb} #{path} #{opts.reject { |k, _| k == :params || k == :input }.map { |k, v| "#{k}=#{v}" }.join(' ')}".strip
  begin
    res, headers = call(jar, verb, path, opts)
    record.call(label, res, headers)
    res
  rescue Exception => e # rubocop:disable Lint/RescueException
    File.write(File.join(out_dir, format("%02d.txt", index)), "#{label}\nRAISED #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 300]}\n")
    summary << "#{format('%02d', index)} #{label} -> RAISED #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 160]}"
    index += 1
    nil
  end
end

jar = Jar.new
login_page = step.call(jar, "GET", "/login")
token = token_from(login_page&.body)
step.call(jar, "POST", "/login", params: { authenticity_token: token, email_address: user.email_address, password: "passw0rd-r4" })
step.call(jar, "POST", "/login", params: { authenticity_token: "wrong", email_address: user.email_address, password: "passw0rd-r4" }) && nil
home = step.call(jar, "GET", "/")
token = token_from(home&.body) || token
File.write(File.join(out_dir, "jar.json"), JSON.generate(jar.cookies))

[
  ["GET", "/settings", {}],
  ["HEAD", "/settings", {}],
  ["GET", "/org/r4org", {}],
  ["GET", "/org/r4org/settings", {}],
  ["GET", "/org/r4org/servers/new", {}],
  ["GET", "/org/r4org/ip_pools", {}],
  ["GET", "/org/r4org/delete", {}],
  ["GET", "/organizations/new", {}],
  ["GET", "/users", {}],
  ["GET", "/users/new", {}],
  ["GET", "/ip_pools", {}],
  ["GET", "/ip_pools/new", {}],
  ["GET", "/ip", {}],
  ["GET", "/org/nosuchorg", {}],
  ["HEAD", "/org/nosuchorg", {}],
  ["GET", "/org/nosuchorg", { "HTTP_ACCEPT" => "application/json" }],
  ["GET", "/users/99999999", {}],
  ["GET", "/org/r4org/servers/nosuch/messages", {}],
  ["GET", "/settings.xml", {}],
  ["GET", "/settings.json", {}],
  ["GET", "/settings", { "HTTP_ACCEPT" => "application/json;q=0.9, text/html;level=1" }],
  ["GET", "/settings", { "HTTP_ACCEPT" => "text/html; charset=utf-8" }],
  ["GET", "/settings", { "HTTP_ACCEPT" => "application/json" }],
  ["GET", "/settings", { "HTTP_ACCEPT" => "text/javascript, application/javascript, */*; q=0.01", "HTTP_X_REQUESTED_WITH" => "XMLHttpRequest" }],
  ["FOO", "/settings", {}],
  ["PROPFIND", "/settings", {}],
  ["OPTIONS", "/settings", {}],
  ["POST", "/settings", {}],
  ["PATCH", "/settings", { params: { user: { first_name: "", last_name: "Probe", email_address: "r4@example.com" }, password: "passw0rd-r4" } }],
  ["PATCH", "/settings", { params: { authenticity_token: token, user: { first_name: "", last_name: "Probe", email_address: "r4@example.com" }, password: "passw0rd-r4" } }],
  ["PATCH", "/settings", { "HTTP_ACCEPT" => "application/json", "HTTP_X_CSRF_TOKEN" => token.to_s,
                           params: { user: { first_name: "", last_name: "Probe", email_address: "r4@example.com" }, password: "passw0rd-r4" } }],
  ["PATCH", "/settings", { "HTTP_ACCEPT" => "application/json", "HTTP_X_CSRF_TOKEN" => token.to_s,
                           params: { user: { first_name: "Rfour", last_name: "Probe", email_address: "r4@example.com", time_zone: "Astana" }, password: "passw0rd-r4" } }],
  ["PATCH", "/settings", { "HTTP_X_CSRF_TOKEN" => token.to_s, params: { password: "passw0rd-r4" } }],
  ["PATCH", "/org/r4org/settings", { "HTTP_X_CSRF_TOKEN" => token.to_s, params: { organization: { name: "" } } }],
  ["POST", "/organizations", { "HTTP_ACCEPT" => "application/json", "HTTP_X_CSRF_TOKEN" => token.to_s, params: { organization: { name: "", permalink: "bad permalink!" } } }],
  ["POST", "/users", { "HTTP_ACCEPT" => "application/json", "HTTP_X_CSRF_TOKEN" => token.to_s, params: { user: { email_address: "not-an-address" } } }],
  ["POST", "/ip_pools", { "HTTP_ACCEPT" => "application/json", "HTTP_X_CSRF_TOKEN" => token.to_s, params: { ip_pool: { name: "" } } }],
  ["POST", "/login/reset", { "HTTP_X_CSRF_TOKEN" => token.to_s, params: { email_address: "nobody@example.com" } }],
  ["GET", "/login/reset", {}],
  ["POST", "/persist", { "HTTP_X_CSRF_TOKEN" => token.to_s }],
  ["GET", "/settings?user[first_name]=x&user=y", {}],
  ["GET", "/settings", { "HTTP_X_FORWARDED_FOR" => "203.0.113.9, 10.0.0.1", "HTTP_X_FORWARDED_PROTO" => "https" }],
  ["GET", "/settings", { "HTTP_IF_NONE_MATCH" => "W/\"nope\"" }]
].each { |verb, path, opts| step.call(jar, verb, path, opts) }

# the user's zone is now Astana if that PATCH succeeded; one page that prints a time in it
step.call(jar, "GET", "/settings")
user.reload.update_columns(time_zone: "London")

if other_jar && File.exist?(other_jar)
  theirs = Jar.new(JSON.parse(File.read(other_jar)))
  page = step.call(theirs, "GET", "/settings", "HTTP_X_R4" => "other-version-cookies")
  their_token = token_from(page&.body)
  step.call(theirs, "PATCH", "/settings", "HTTP_ACCEPT" => "application/json", "HTTP_X_CSRF_TOKEN" => their_token.to_s, "HTTP_X_R4" => "other-version-cookies",
                                          params: { user: { first_name: "", last_name: "Probe", email_address: "r4@example.com" }, password: "passw0rd-r4" })
end

# The first run logged out here, which ended the session whose cookies the other
# version was about to replay. R4_NO_LOGOUT=1 keeps it open for the replay run.
unless ENV["R4_NO_LOGOUT"]
  step.call(jar, "DELETE", "/logout", "HTTP_X_CSRF_TOKEN" => token.to_s)
  step.call(jar, "GET", "/settings")
end

# every mail the application sends, rendered
ActionMailer::Base.delivery_method = :test
mails = {}
begin
  server = Server.new(organization: org, name: "R4 Server", permalink: "r4server", mode: "Live")
  domain = Domain.new(name: "r4.example.com", owner: org, verification_token: "tok123", verification_method: "Email") rescue Domain.new(name: "r4.example.com")
  user.password_reset_token = "resettoken"
  {
    password_reset: -> { AppMailer.password_reset(user, "/org/r4org") },
    password_reset_no_return: -> { AppMailer.password_reset(user) },
    verify_domain: -> { AppMailer.verify_domain(domain, "owner@r4.example.com", user) },
    server_send_limit_approaching: -> { AppMailer.server_send_limit_approaching(server) },
    server_send_limit_exceeded: -> { AppMailer.server_send_limit_exceeded(server) },
    server_suspended: -> { AppMailer.server_suspended(server) },
    test_message: -> { AppMailer.test_message("to@example.com") }
  }.each do |name, build|
    mails[name] = begin
      build.call.message.encoded.gsub(/^Message-ID: .*$/, "Message-ID: X").gsub(/^Date: .*$/, "Date: X").gsub(/[0-9a-f]{8}-[0-9a-f-]{27}/, "UUID")
    rescue Exception => e # rubocop:disable Lint/RescueException
      "RAISED #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 200]}"
    end
  end
end
File.write(File.join(out_dir, "mails.txt"), mails.map { |k, v| "#### #{k}\n#{v}\n" }.join)

# schema as this version dumps it
begin
  io = StringIO.new
  ActiveRecord::Base.connection_pool.with_connection do |c|
    if ActiveRecord::SchemaDumper.method(:dump).arity.abs >= 1 && Rails.version >= "7.2"
      ActiveRecord::SchemaDumper.dump(ActiveRecord::Base.connection_pool, io)
    else
      ActiveRecord::SchemaDumper.dump(c, io)
    end
  end
  File.write(File.join(out_dir, "schema.rb"), io.string)
rescue Exception => e # rubocop:disable Lint/RescueException
  File.write(File.join(out_dir, "schema.rb"), "RAISED #{e.class}: #{e.message}")
end

middleware = Rails.application.middleware.map { |m| m.respond_to?(:name) ? m.name.to_s : m.inspect }
cfg = Rails.application.config
File.write(File.join(out_dir, "settings.txt"), [
  "middleware:", *middleware,
  "default_headers: #{cfg.action_dispatch.default_headers.inspect}",
  "cookies_serializer: #{cfg.action_dispatch.cookies_serializer.inspect}",
  "per_form_csrf_tokens: #{ActionController::Base.per_form_csrf_tokens.inspect}",
  "forgery_protection_origin_check: #{ActionController::Base.forgery_protection_origin_check.inspect}",
  "cookies_same_site_protection: #{cfg.action_dispatch.cookies_same_site_protection.inspect}",
  "use_authenticated_cookie_encryption: #{cfg.action_dispatch.use_authenticated_cookie_encryption.inspect}",
  "key_generator_hash_digest_class: #{cfg.active_support.key_generator_hash_digest_class.inspect}",
  "hash_digest_class: #{ActiveSupport::Digest.hash_digest_class.inspect}",
  "message_serializer: #{(ActiveSupport::Messages::Codec.default_serializer rescue cfg.active_support.message_serializer).inspect}",
  "use_message_serializer_for_metadata: #{(ActiveSupport::Messages::Metadata.use_message_serializer_for_metadata rescue nil).inspect}",
  "default_charset: #{ActionDispatch::Response.default_charset.inspect}",
  "time_zone default: #{Time.zone_default&.name.inspect}",
  "active_record: belongs_to_required=#{ActiveRecord::Base.belongs_to_required_by_default.inspect} partial_inserts=#{ActiveRecord::Base.partial_inserts.inspect} " \
  "default_column_serializer=#{ActiveRecord::Base.default_column_serializer.inspect} run_commit_callbacks_on_first=#{(ActiveRecord.run_after_transaction_callbacks_in_order_defined rescue nil).inspect}",
  "eager_load: #{cfg.eager_load.inspect} cache_store: #{Rails.cache.class}",
  "log_tags: #{cfg.log_tags.inspect} logger: #{Rails.logger.class}",
  "console defined at this point: #{Rails.const_defined?('Console').inspect} rake defined: #{defined?(Rake).inspect}"
].join("\n") + "\n")

File.write(File.join(out_dir, "summary.txt"), summary.join("\n") + "\n")
File.write(File.join(out_dir, "meta.txt"), "rails #{Rails.version} env #{Rails.env} deprecations=#{deprecations.uniq.size}\n#{deprecations.uniq.join("\n")}\n")
