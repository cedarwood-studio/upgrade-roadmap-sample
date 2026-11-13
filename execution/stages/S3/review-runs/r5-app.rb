# frozen_string_literal: true

# Fifth review, S3. Run in production with a fixed secret key, once on each
# version, against the same main database and the same message database:
#   bundle exec ruby /out/r5-app.rb <out_dir>
# The fourth review walked the organization-level pages. This one walks what it
# left: every server-level page (15 controllers the suite never loads, and the
# message pages, of which the suite runs 27 of 135 lines), with a real message
# database behind them, plus the legacy API and the two mails that need a
# message database. The data is created once with fixed values, so the second
# and third runs read the same rows and their output can be compared with diff.

require "fileutils"
require "json"
out_dir = ARGV[0] || "/tmp/r5"
FileUtils.mkdir_p(out_dir)

require "rack"
require "rack/mock"
built = Rack::Builder.parse_file(File.expand_path("config.ru", Dir.pwd))
APP = built.is_a?(Array) ? built.first : built
HOST = Postal::Config.postal.web_hostname

deprecations = []
ActiveSupport::Notifications.subscribe("deprecation.rails") { |*, payload| deprecations << payload[:message].to_s[0, 200] }

setup_notes = []
attempt = lambda do |name, &block|
  block.call
rescue Exception => e # rubocop:disable Lint/RescueException
  setup_notes << "SETUP-FAIL #{name}: #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 200]}"
  nil
end

FIXED = Time.utc(2026, 6, 1, 12, 0, 0)

user = User.find_by(email_address: "r5@example.com") ||
       User.create!(first_name: "Rfive", last_name: "Probe", email_address: "r5@example.com", password: "passw0rd-r5",
                    email_verified_at: FIXED, admin: true, time_zone: "London")
org = Organization.find_by(permalink: "r5org") || Organization.create!(name: "R5 Org", permalink: "r5org", owner: user)

make_server = lambda do |permalink|
  Server.find_by(permalink: permalink) || begin
    s = org.servers.build(name: "R5 #{permalink}", mode: "Live", permalink: permalink)
    s.save!
    s.update_columns(uuid: "00000000-0000-4000-8000-#{permalink.ljust(12, '0')[0, 12].tr('^0-9a-f', '0')}", token: "tok#{permalink}"[0, 6],
                     created_at: FIXED, updated_at: FIXED)
    s
  end
end
server = attempt.call("server") { make_server.call("r5server") }
api_server = attempt.call("api server") { make_server.call("r5api") }

fix = lambda do |record, n|
  cols = { "uuid" => "00000000-0000-4000-8000-00000000000#{n}", "created_at" => FIXED, "updated_at" => FIXED }
  record.update_columns(cols.slice(*record.class.column_names))
  record
end

domain = attempt.call("domain") do
  server.domains.find_by(name: "r5.example.com") || begin
    d = server.domains.create!(name: "r5.example.com", verification_method: "DNS")
    d.update_columns(verified_at: FIXED, verification_token: "verifytoken", dkim_identifier_string: "r5dkim")
    fix.call(d, 1)
  end
end
attempt.call("api domain") do
  api_server.domains.find_by(name: "r5api.example.com") || begin
    d = api_server.domains.create!(name: "r5api.example.com", verification_method: "DNS")
    d.update_columns(verified_at: FIXED)
    d
  end
end
credential = attempt.call("credential") do
  server.credentials.find_by(name: "r5 key") || begin
    c = server.credentials.create!(type: "API", name: "r5 key")
    c.update_columns(key: "r5fixedkey0000000000000A")
    fix.call(c, 2)
  end
end
api_credential = attempt.call("api credential") do
  api_server.credentials.find_by(name: "r5 api key") || begin
    c = api_server.credentials.create!(type: "API", name: "r5 api key")
    c.update_columns(key: "r5apikey00000000000000AB")
    c
  end
end
http_endpoint = attempt.call("http endpoint") do
  server.http_endpoints.find_by(name: "r5 http") ||
    fix.call(server.http_endpoints.create!(name: "r5 http", url: "https://example.com/in", encoding: "BodyAsJSON", format: "Hash", timeout: 5), 3)
end
smtp_endpoint = attempt.call("smtp endpoint") do
  server.smtp_endpoints.find_by(name: "r5 smtp") ||
    fix.call(server.smtp_endpoints.create!(name: "r5 smtp", hostname: "mx.example.com", port: 25, ssl_mode: "Auto"), 4)
end
address_endpoint = attempt.call("address endpoint") do
  server.address_endpoints.find_by(address: "r5@forward.example.com") ||
    fix.call(server.address_endpoints.create!(address: "r5@forward.example.com"), 5)
end
route = attempt.call("route") do
  server.routes.find_by(name: "r5route") || begin
    r = server.routes.create!(name: "r5route", domain: domain, spam_mode: "Mark", _endpoint: "HTTPEndpoint##{http_endpoint.uuid}")
    r.update_columns(token: "r5tokn")
    fix.call(r, 6)
  end
end
webhook = attempt.call("webhook") do
  server.webhooks.find_by(name: "r5 hook") ||
    fix.call(server.webhooks.create!(name: "r5 hook", url: "https://example.com/hook", all_events: true, enabled: true), 7)
end
track_domain = attempt.call("track domain") do
  server.track_domains.find_by(name: "click") || begin
    t = server.track_domains.create!(name: "click", domain: domain)
    t.update_columns(dns_status: "OK", dns_checked_at: FIXED)
    fix.call(t, 8)
  end
end
ip_pool = attempt.call("ip pool") do
  IPPool.find_by(name: "r5 pool") || begin
    p = IPPool.create!(name: "r5 pool")
    p.ip_addresses.create!(ipv4: "10.55.0.5", hostname: "r5.example.com")
    org.ip_pools << p unless org.ip_pools.include?(p)
    fix.call(p, 9)
  end
end
ip_pool_rule = attempt.call("ip pool rule") do
  server.ip_pool_rules.first || fix.call(server.ip_pool_rules.create!(ip_pool: ip_pool, to_text: "example.org", from_text: ""), 0)
end

# messages, created once
db = attempt.call("message db") { server.message_db }
message_ids = []
attempt.call("messages") do
  count = db.query("SELECT COUNT(id) AS c FROM `#{db.database_name}`.`messages`").first["c"].to_i
  if count.zero?
    plain = Mail.new
    plain.to = "john@example.com"
    plain.from = "test@r5.example.com"
    plain.subject = "An example message"
    plain.body = "Hello world!"
    plain.message_id = "<r5-plain@r5.example.com>"
    plain.date = FIXED

    rich = Mail.new
    rich.to = "jane@example.com"
    rich.from = "test@r5.example.com"
    rich.subject = "Rich & <b>bold</b> über"
    rich.message_id = "<r5-rich@r5.example.com>"
    rich.date = FIXED
    rich.text_part = Mail::Part.new { body "Plain part\nhttps://example.com/a?b=1&c=2" }
    rich.html_part = Mail::Part.new do
      content_type "text/html; charset=UTF-8"
      body "<html><body><p>Hello <a href='https://example.com/a?b=1'>link</a></p><script>alert(1)</script></body></html>"
    end
    rich.add_file(filename: "note.txt", content: "attached text")

    inbound = Mail.new
    inbound.to = "r5route@r5.example.com"
    inbound.from = "sender@example.org"
    inbound.subject = "Incoming"
    inbound.body = "Inbound body\n\n> quoted"
    inbound.message_id = "<r5-in@example.org>"
    inbound.date = FIXED

    [[plain, "outgoing", "john@example.com", "test@r5.example.com", "Sent"],
     [rich, "outgoing", "jane@example.com", "test@r5.example.com", "SoftFail"],
     [plain, "outgoing", "held@example.com", "test@r5.example.com", "Held"],
     [inbound, "incoming", "r5route@r5.example.com", "sender@example.org", "Sent"]].each do |mail, scope, to, from, status|
      m = db.new_message
      m.scope = scope
      m.rcpt_to = to
      m.mail_from = from
      m.domain_id = domain.id if scope == "outgoing"
      m.credential_id = credential.id if scope == "outgoing"
      m.route_id = route.id if scope == "incoming"
      m.raw_message = mail.to_s
      m.save(queue_on_create: false)
      m.create_delivery(status, details: "r5 #{status.downcase} details", output: "250 2.0.0 OK r5", sent_with_ssl: true, log_id: "R5LOG")
      m.update(spam_score: 1.5, spam_status: "NotSpam", threat: false, tag: "r5tag") rescue nil
    end
    db.query("UPDATE `#{db.database_name}`.`messages` SET timestamp = #{FIXED.to_f}, last_delivery_attempt = #{FIXED.to_f}, token = CONCAT('r5tok', id)")
    db.query("UPDATE `#{db.database_name}`.`deliveries` SET timestamp = #{FIXED.to_f}")
    db.query("UPDATE `#{db.database_name}`.`messages` SET held = 1, hold_expiry = #{(FIXED + 7.days).to_f} WHERE status = 'Held'")
    attempt.call("suppression") { db.suppression_list.add(:recipient, "bounced@example.com", reason: "r5 too many soft fails") }
    attempt.call("suppression fix") { db.query("UPDATE `#{db.database_name}`.`suppressions` SET timestamp = #{FIXED.to_f}, keep_until = #{(FIXED + 30.days).to_f}") }
  end
  message_ids = db.query("SELECT id FROM `#{db.database_name}`.`messages` ORDER BY id").map { |r| r["id"] }
end

VOLATILE = %w[x-request-id x-runtime date etag set-cookie content-length server-timing].freeze

class Jar
  attr_reader :cookies

  def initialize
    @cookies = {}
  end

  def header
    @cookies.map { |k, v| "#{k}=#{v}" }.join("; ")
  end

  def absorb(headers)
    Array(headers["set-cookie"]).join("\n").split("\n").each do |line|
      name, value = line.split(";").first.to_s.split("=", 2)
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
      .gsub(/"time":[0-9.e-]+/, '"time":N')
end

def token_from(body)
  body.to_s[/csrf-token" content="([^"]+)/, 1] || body.to_s[/authenticity_token" value="([^"]+)/, 1]
end

summary = []
index = 0
step = lambda do |jar, verb, path, opts = {}|
  mask = opts.delete(:mask)
  label = "#{verb} #{path} #{opts.reject { |k, _| k == :params || k == :input || k == 'HTTP_X_CSRF_TOKEN' }.map { |k, v| "#{k}=#{v.to_s[0, 40]}" }.join(' ')}".strip
  label = label.sub(%r{webhooks/[0-9a-f-]{36}}) { |m| m.include?("00000000-0000-4000") ? m : "webhooks/TEMP" }
  begin
    res, headers = call(jar, verb, path, opts)
    body = normalize(res.body)
    body = mask.call(body) if mask
    kept = headers.reject { |k, _| VOLATILE.include?(k) }.sort.map { |k, v| "#{k}: #{v}" }
    text = [label, "status: #{res.status}", *kept, "body-bytes: #{body.bytesize}", "", body].join("\n")
    File.write(File.join(out_dir, format("%03d.txt", index)), text)
    summary << "#{format('%03d', index)} #{label} -> #{res.status} #{headers['content-type']} #{body.bytesize}b loc=#{headers['location']}"
    index += 1
    res
  rescue Exception => e # rubocop:disable Lint/RescueException
    File.write(File.join(out_dir, format("%03d.txt", index)), "#{label}\nRAISED #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 300]}\n")
    summary << "#{format('%03d', index)} #{label} -> RAISED #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 160]}"
    index += 1
    nil
  end
end

jar = Jar.new
login_page = step.call(jar, "GET", "/login")
token = token_from(login_page&.body)
step.call(jar, "POST", "/login", params: { authenticity_token: token, email_address: user.email_address, password: "passw0rd-r5" })
home = step.call(jar, "GET", "/")
token = token_from(home&.body) || token

base = "/org/r5org/servers/r5server"
gets = %w[ /edit /limits /retention /queue /spam /delete /advanced /help/outgoing /help/incoming
           /messages /messages/outgoing /messages/incoming /messages/held /messages/suppressions /messages/new
           /messages/outgoing?query=to:john@example.com /messages/outgoing?query=status:softfail+tag:r5tag
           /messages/outgoing?query=before:2026-07-01+after:2026-05-01 /messages/outgoing?query=nonsense:: /messages/outgoing?page=2
           /messages/incoming?query=from:sender@example.org
           /domains /domains/new /credentials /credentials/new /routes /routes/new /http_endpoints /http_endpoints/new
           /smtp_endpoints /smtp_endpoints/new /address_endpoints /address_endpoints/new /track_domains /track_domains/new
           /ip_pool_rules /ip_pool_rules/new /webhooks /webhooks/new /webhooks/history /webhooks/history?page=2 ]
gets.unshift("")
{ "domains" => [domain, %w[/setup /verify]], "credentials" => [credential, %w[/edit]], "routes" => [route, %w[/edit]],
  "http_endpoints" => [http_endpoint, %w[/edit]], "smtp_endpoints" => [smtp_endpoint, %w[/edit]],
  "address_endpoints" => [address_endpoint, %w[/edit]], "track_domains" => [track_domain, %w[/edit]],
  "ip_pool_rules" => [ip_pool_rule, %w[/edit]], "webhooks" => [webhook, %w[/edit]] }.each do |name, (record, suffixes)|
  next unless record

  suffixes.each { |s| gets << "/#{name}/#{record.to_param}#{s}" }
  gets << "/#{name}/00000000-0000-4000-8000-ffffffffffff/edit"
end
message_ids.each do |id|
  ["", "/activity", "/plain", "/html", "/html_raw", "/attachments", "/headers", "/deliveries", "/spam_checks", "/download",
   "/attachment?attachment=0"].each { |s| gets << "/messages/#{id}#{s}" }
end
gets << "/messages/999999" << "/messages/999999/deliveries"

gets.each { |p| step.call(jar, "GET", base + p) }
["/messages/outgoing", "/messages/incoming", "/queue", "/webhooks/history", "/messages/#{message_ids.first}/deliveries", "/messages/#{message_ids.first}",
 "/credentials", "/domains"].each do |p|
  step.call(jar, "GET", base + p, "HTTP_ACCEPT" => "application/json")
  step.call(jar, "GET", base + p, "HTTP_ACCEPT" => "text/javascript, */*; q=0.01", "HTTP_X_REQUESTED_WITH" => "XMLHttpRequest")
end
["/org/r5org", "/org/r5org/domains", "/org/r5org/domains/new", "/org/r5org/ip_pool_rules", "/org/r5org/ip_pool_rules/new", "/org/r5org/ip_pools",
 "/org/r5org/servers/new", "/org/r5org/servers/nosuch", "/ip_pools/#{ip_pool&.to_param}", "/ip_pools/#{ip_pool&.to_param}/edit",
 "/ip_pools/#{ip_pool&.to_param}/ip_addresses/new", "/.well-known/jwks.json"].each { |p| step.call(jar, "GET", p) }

# forms that fail validation, as the browser sends them (HTML) and as the remote forms send them (JSON)
csrf = { "HTTP_X_CSRF_TOKEN" => token.to_s }
{ "domains" => { domain: { name: "not a domain", verification_method: "DNS" } },
  "credentials" => { credential: { type: "SMTP-IP", name: "", key: "not-an-ip" } },
  "routes" => { route: { name: "bad name!", domain_id: "", spam_mode: "Mark", _endpoint: "Nope#1" } },
  "http_endpoints" => { http_endpoint: { name: "", url: "ftp://nope", encoding: "X", format: "Y", timeout: 900 } },
  "smtp_endpoints" => { smtp_endpoint: { name: "", hostname: "bad host!", port: 0, ssl_mode: "Nope" } },
  "address_endpoints" => { address_endpoint: { address: "not-an-address" } },
  "track_domains" => { track_domain: { name: "", domain_id: "" } },
  "ip_pool_rules" => { ip_pool_rule: { from_text: "", to_text: "", ip_pool_id: "" } },
  "webhooks" => { webhook: { name: "", url: "nope", all_events: "0", enabled: "1" } } }.each do |name, params|
  step.call(jar, "POST", "#{base}/#{name}", csrf.merge(params: params))
  step.call(jar, "POST", "#{base}/#{name}", csrf.merge("HTTP_ACCEPT" => "application/json", params: params))
  step.call(jar, "POST", "#{base}/#{name}", csrf.merge(params: {}))
end
step.call(jar, "PATCH", base, csrf.merge("HTTP_ACCEPT" => "application/json", params: { server: { name: "" } }))
step.call(jar, "PATCH", "#{base}/credentials/#{credential&.to_param}", csrf.merge("HTTP_ACCEPT" => "application/json", params: { credential: { name: "" } }))
step.call(jar, "PATCH", "#{base}/routes/#{route&.to_param}", csrf.merge("HTTP_ACCEPT" => "application/json", params: { route: { name: "bad name!", _endpoint: "" } }))
step.call(jar, "POST", "/org/r5org/servers", csrf.merge("HTTP_ACCEPT" => "application/json", params: { server: { name: "", mode: "Nope", permalink: "bad permalink" } }))
step.call(jar, "POST", "#{base}/messages", csrf.merge(params: { message: { to: "", from: "", subject: "", plain_body: "" } }))
step.call(jar, "POST", "#{base}/messages/#{message_ids.first}/retry", csrf.merge("HTTP_ACCEPT" => "application/json"))
step.call(jar, "POST", "#{base}/domains/#{domain&.to_param}/check", csrf.merge("HTTP_ACCEPT" => "application/json"))
step.call(jar, "DELETE", "#{base}/delete", csrf)
step.call(jar, "DELETE", base, csrf.merge("HTTP_ACCEPT" => "application/json", params: { confirm_text: "wrong" }))

# a valid create and destroy through the forms, on records this run removes again
created = step.call(jar, "POST", "#{base}/webhooks", csrf.merge("HTTP_ACCEPT" => "application/json", params: { webhook: { name: "r5 temp", url: "https://example.com/t", all_events: "1", enabled: "1" } }))
temp = server.webhooks.find_by(name: "r5 temp")
summary << "temp webhook created: #{!temp.nil?} #{created&.status}"
step.call(jar, "DELETE", "#{base}/webhooks/#{temp.uuid}", csrf.merge("HTTP_ACCEPT" => "application/json", mask: ->(b) { b.gsub(temp.uuid, "TEMP") })) if temp
summary << "temp webhook removed: #{server.webhooks.where(name: 'r5 temp').none?}"
server.webhooks.where(name: "r5 temp").destroy_all

# the legacy API, on its own server so the pages above keep reading the same rows
api = lambda do |path, payload, key = "r5apikey00000000000000AB"|
  mask = lambda do |b|
    b.gsub(/"id":\d+/, '"id":N').gsub(/"token":"[^"]+"/, '"token":"T"').gsub(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/, "UUID")
     .gsub(/"timestamp":[0-9.]+/, '"timestamp":N').gsub(/"hold_expiry":[0-9.]+/, '"hold_expiry":N')
  end
  step.call(Jar.new, "POST", path, "CONTENT_TYPE" => "application/json", "HTTP_X_SERVER_API_KEY" => key, input: JSON.generate(payload), mask: mask)
end
sent = api.call("/api/v1/send/message", { to: ["john@example.com"], cc: ["cc@example.com"], from: "test@r5api.example.com", subject: "r5 api", plain_body: "hi",
                                          html_body: "<p>hi</p>", headers: { "X-R5" => "1" }, attachments: [{ name: "a.txt", content_type: "text/plain", data: "aGk=" }] })
sent_id = begin
  JSON.parse(sent.body).dig("data", "messages", "john@example.com", "id")
rescue StandardError
  nil
end
api.call("/api/v1/send/message", { to: [], from: "test@r5api.example.com" })
api.call("/api/v1/send/message", { to: ["john@example.com"], from: "test@unverified.example.net", subject: "x", plain_body: "x" })
api.call("/api/v1/send/message", { to: ["john@example.com"], from: "test@r5api.example.com", subject: "x", plain_body: "x" }, "wrongkey")
api.call("/api/v1/send/raw", { mail_from: "test@r5api.example.com", rcpt_to: ["raw@example.com"], data: ["Subject: raw\r\nFrom: test@r5api.example.com\r\nTo: raw@example.com\r\n\r\nraw body\r\n"].pack("m0") })
api.call("/api/v1/messages/message", { id: sent_id, _expansions: true })
api.call("/api/v1/messages/message", { id: sent_id, _expansions: %w[status details inspection plain_body html_body attachments headers raw_message activity_entries] })
api.call("/api/v1/messages/message", { id: 99_999_999 })
api.call("/api/v1/messages/deliveries", { id: sent_id })
step.call(Jar.new, "POST", "/api/v1/send/message", "CONTENT_TYPE" => "application/json", "HTTP_X_SERVER_API_KEY" => "r5apikey00000000000000AB", input: "{not json")
step.call(Jar.new, "GET", "/api/v1/send/message?to[]=a@example.com", "HTTP_X_SERVER_API_KEY" => "r5apikey00000000000000AB")
QueuedMessage.where(server_id: api_server.id).delete_all if api_server

# the two mails the fourth review could not render without a message database
ActionMailer::Base.delivery_method = :test
mails = {
  server_send_limit_approaching: -> { AppMailer.server_send_limit_approaching(server) },
  server_send_limit_exceeded: -> { AppMailer.server_send_limit_exceeded(server) },
  server_suspended: -> { AppMailer.server_suspended(server) }
}.map do |name, build|
  text = begin
    build.call.message.encoded.gsub(/^Message-ID: .*$/, "Message-ID: X").gsub(/^Date: .*$/, "Date: X")
  rescue Exception => e # rubocop:disable Lint/RescueException
    "RAISED #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 200]}"
  end
  "#### #{name}\n#{text}\n"
end
File.write(File.join(out_dir, "mails.txt"), mails.join)

# values behind the pages, straight from the models
facts = []
fact = lambda do |name, &block|
  facts << "#{name}: #{block.call.inspect[0, 300]}"
rescue Exception => e # rubocop:disable Lint/RescueException
  facts << "#{name}: RAISED #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 200]}"
end
h = ApplicationController.helpers
fact.call("total_size class and rendering") { [db.total_size.class.name, h.number_to_human_size(db.total_size)] }
fact.call("message count, statuses") { db.query("SELECT status, COUNT(*) AS c FROM `#{db.database_name}`.`messages` GROUP BY status ORDER BY status").map(&:values) }
fact.call("route description, forward address") { [route.description, route.forward_address] }
fact.call("route with a bad endpoint: errors") { r = server.routes.build(name: "x", domain: domain, _endpoint: "Nope#1", spam_mode: "Mark"); [r.valid?, r.errors.full_messages] }
fact.call("additional route endpoints: errors") { r = server.routes.find(route.id); r.additional_route_endpoints_array = ["HTTPEndpoint#nope"]; [r.save, r.errors.full_messages] }
fact.call("credential options round trip") { c = server.credentials.find(credential.id); [c.options.class.name, c.options, Credential.type_for_attribute(:options).coder.class.name] }
fact.call("server stats and queue") { [server.queue_size, server.held_messages, server.message_rate.class.name, server.bounce_rate, server.domain_stats] }
fact.call("throughput stats") { server.throughput_stats.transform_values { |v| v.is_a?(Numeric) ? v.class.name : v } }
fact.call("domain dns records") { [domain.spf_record, domain.dkim_record_name, domain.return_path_domain] }
fact.call("webhook request serialize") do
  w = WebhookRequest.create!(server_id: server.id, webhook_id: webhook.id, url: "https://example.com/hook", event: "MessageSent", uuid: SecureRandom.uuid, payload: { "a" => [1, { "b" => nil }] })
  raw = WebhookRequest.connection.select_value("SELECT payload FROM webhook_requests WHERE id = #{w.id}")
  out = [w.reload.payload, raw]
  w.destroy
  out
end
fact.call("user with org and to_json") { user.as_json(only: %i[first_name time_zone admin]) }
fact.call("in_batches over stale locks") { n = 0; QueuedMessage.with_stale_lock.in_batches { |b| n += b.size }; n }
fact.call("organization destroy guard") { o = Organization.find(org.id); [o.servers.present.count, o.respond_to?(:soft_destroy)] }
File.write(File.join(out_dir, "facts.txt"), facts.join("\n") + "\n")

File.write(File.join(out_dir, "summary.txt"), summary.join("\n") + "\n")
File.write(File.join(out_dir, "meta.txt"), "rails #{Rails.version} env #{Rails.env} deprecations=#{deprecations.uniq.size} messages=#{message_ids.size}\n#{deprecations.uniq.join("\n")}\n#{setup_notes.join("\n")}\n")
