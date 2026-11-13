# frozen_string_literal: true

# Review of S4. Run in production with a fixed secret key, once on each version,
# against the same main database and the same message database:
#   bundle exec ruby /out/s4-app.rb <out_dir>
# Walks the pages as a signed-in user through config.ru, the password reset flow
# as a browser does it, HEAD and GET on error pages, the legacy API, the mails,
# and then calls the framework lines the suite loads and never runs. The data is
# created once with fixed values so later runs read the same rows.

require "fileutils"
require "json"
out_dir = ARGV[0] || "/tmp/s4"
FileUtils.mkdir_p(out_dir)

require "rack"
require "rack/mock"
built = Rack::Builder.parse_file(File.expand_path("config.ru", Dir.pwd))
APP = built.is_a?(Array) ? built.first : built
HOST = Postal::Config.postal.web_hostname
ActionMailer::Base.delivery_method = :test

deprecations = []
ActiveSupport::Notifications.subscribe("deprecation.rails") { |*, payload| deprecations << payload[:message].to_s[0, 200] }

notes = []
attempt = lambda do |name, &block|
  block.call
rescue Exception => e # rubocop:disable Lint/RescueException
  notes << "SETUP-FAIL #{name}: #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 200]}"
  nil
end

FIXED = Time.utc(2026, 6, 1, 12, 0, 0)
user = User.find_by(email_address: "s4@example.com") ||
       User.create!(first_name: "Sfour", last_name: "Probe", email_address: "s4@example.com", password: "passw0rd-s4",
                    email_verified_at: FIXED, admin: true, time_zone: "London")
user.update!(password: "passw0rd-s4") unless user.authenticate("passw0rd-s4")
org = Organization.find_by(permalink: "s4org") || Organization.create!(name: "S4 Org", permalink: "s4org", owner: user)
server = attempt.call("server") do
  Server.find_by(permalink: "s4server") || begin
    s = org.servers.build(name: "S4 server", mode: "Live", permalink: "s4server")
    s.save!
    s.update_columns(uuid: "00000000-0000-4000-8000-000000000054", token: "tokens", created_at: FIXED, updated_at: FIXED)
    s
  end
end
fix = lambda do |record, n|
  cols = { "uuid" => "00000000-0000-4000-8000-00000000000#{n}", "created_at" => FIXED, "updated_at" => FIXED }
  record.update_columns(cols.slice(*record.class.column_names))
  record
end
domain = attempt.call("domain") do
  server.domains.find_by(name: "s4.example.com") || begin
    d = server.domains.create!(name: "s4.example.com", verification_method: "DNS")
    d.update_columns(verified_at: FIXED, verification_token: "verifytoken", dkim_identifier_string: "s4dkim")
    fix.call(d, 1)
  end
end
credential = attempt.call("credential") do
  server.credentials.find_by(name: "s4 key") || begin
    c = server.credentials.create!(type: "API", name: "s4 key")
    c.update_columns(key: "s4fixedkey0000000000000A")
    fix.call(c, 2)
  end
end
http_endpoint = attempt.call("http endpoint") do
  server.http_endpoints.find_by(name: "s4 http") ||
    fix.call(server.http_endpoints.create!(name: "s4 http", url: "https://example.com/in", encoding: "BodyAsJSON", format: "Hash", timeout: 5), 3)
end
route = attempt.call("route") do
  server.routes.find_by(name: "s4route") || begin
    r = server.routes.create!(name: "s4route", domain: domain, spam_mode: "Mark", _endpoint: "HTTPEndpoint##{http_endpoint.uuid}")
    r.update_columns(token: "s4tokn")
    fix.call(r, 6)
  end
end
webhook = attempt.call("webhook") do
  server.webhooks.find_by(name: "s4 hook") ||
    fix.call(server.webhooks.create!(name: "s4 hook", url: "https://example.com/hook", all_events: true, enabled: true), 7)
end
ip_pool = attempt.call("ip pool") do
  IPPool.find_by(name: "s4 pool") || begin
    p = IPPool.create!(name: "s4 pool")
    p.ip_addresses.create!(ipv4: "10.54.0.5", hostname: "s4.example.com")
    org.ip_pools << p unless org.ip_pools.include?(p)
    fix.call(p, 9)
  end
end
attempt.call("server uses pool") { server.update_columns(ip_pool_id: ip_pool.id) }

db = attempt.call("message db") { server.message_db }
message_ids = []
attempt.call("messages") do
  count = db.query("SELECT COUNT(id) AS c FROM `#{db.database_name}`.`messages`").first["c"].to_i
  if count.zero?
    plain = Mail.new
    plain.to = "john@example.com"
    plain.from = "test@s4.example.com"
    plain.subject = "An example message"
    plain.body = "Hello world!"
    plain.message_id = "<s4-plain@s4.example.com>"
    plain.date = FIXED
    rich = Mail.new
    rich.to = "jane@example.com"
    rich.from = "test@s4.example.com"
    rich.subject = "Rich & <b>bold</b> über"
    rich.message_id = "<s4-rich@s4.example.com>"
    rich.date = FIXED
    rich.text_part = Mail::Part.new { body "Plain part\nhttps://example.com/a?b=1&c=2" }
    rich.html_part = Mail::Part.new do
      content_type "text/html; charset=UTF-8"
      body "<html><body><p>Hello <a href='https://example.com/a?b=1&amp;c=2'>link</a></p><script>alert(1)</script></body></html>"
    end
    rich.add_file(filename: "note.txt", content: "attached text")
    [[plain, "outgoing", "john@example.com", "Sent"], [rich, "outgoing", "jane@example.com", "SoftFail"],
     [plain, "outgoing", "held@example.com", "Held"]].each do |mail, scope, to, status|
      m = db.new_message
      m.scope = scope
      m.rcpt_to = to
      m.mail_from = "test@s4.example.com"
      m.domain_id = domain.id
      m.credential_id = credential.id
      m.raw_message = mail.to_s
      m.save(queue_on_create: false)
      m.create_delivery(status, details: "s4 #{status.downcase} details", output: "250 2.0.0 OK s4", sent_with_ssl: true, log_id: "S4LOG")
      m.update(spam_score: 1.5, spam_status: "NotSpam", threat: false, tag: "s4tag") rescue nil
    end
    db.query("UPDATE `#{db.database_name}`.`messages` SET timestamp = #{FIXED.to_f}, last_delivery_attempt = #{FIXED.to_f}, token = CONCAT('s4tok', id)")
    db.query("UPDATE `#{db.database_name}`.`deliveries` SET timestamp = #{FIXED.to_f}")
    db.query("UPDATE `#{db.database_name}`.`messages` SET held = 1, hold_expiry = #{(FIXED + 7.days).to_f} WHERE status = 'Held'")
    attempt.call("suppression") { db.suppression_list.add(:recipient, "bounced@example.com", reason: "s4 too many soft fails") }
    attempt.call("suppression fix") { db.query("UPDATE `#{db.database_name}`.`suppressions` SET timestamp = #{FIXED.to_f}, keep_until = #{(FIXED + 30.days).to_f}") }
  end
  message_ids = db.query("SELECT id FROM `#{db.database_name}`.`messages` ORDER BY id").map { |r| r["id"] }
end

VOLATILE = %w[x-request-id x-runtime date etag server-timing].freeze

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
      .gsub(/(js-disk-size"[^>]*>)[^<]+/, '\1SIZE')
      .gsub(/(&quot;(?:incoming|outgoing|outgoing_usage)&quot;:)[0-9.]+/, '\1N')
      .gsub(/"size":"\d+"/, '"size":"N"')
      .gsub(/\d{1,2} [A-Z][a-z]{2} 20\d\d \d\d:\d\d:\d\d [+-]\d{4}/, "RFCDATE")
end

# cookie names and attributes, without the values
def cookie_shape(headers)
  Array(headers["set-cookie"]).join("\n").split("\n").map do |line|
    parts = line.split(";").map(&:strip)
    ([parts.first.to_s.split("=", 2).first] + parts[1..].to_a.map { |a| a.sub(/(expires|max-age)=.*/i, '\1=T') }).join("; ")
  end.sort.join(" | ")
end

def token_from(body)
  body.to_s[/csrf-token" content="([^"]+)/, 1] || body.to_s[/authenticity_token" value="([^"]+)/, 1]
end

summary = []
index = 0
step = lambda do |jar, verb, path, opts = {}|
  mask = opts.delete(:mask)
  label = "#{verb} #{path} #{opts.reject { |k, _| k == :params || k == :input || k == 'HTTP_X_CSRF_TOKEN' }.map { |k, v| "#{k}=#{v.to_s[0, 40]}" }.join(' ')}".strip
  label = mask.call(label) if mask
  begin
    res, headers = call(jar, verb, path, opts)
    body = normalize(res.body)
    body = mask.call(body) if mask
    kept = headers.reject { |k, _| VOLATILE.include?(k) || k == "set-cookie" || (k == "content-length" && verb != "HEAD") }
    kept["location"] = mask.call(kept["location"]) if mask && kept["location"]
    kept = kept.sort.map { |k, v| "#{k}: #{v}" }
    text = [label, "status: #{res.status}", *kept, "cookies: #{cookie_shape(headers)}", "body-bytes: #{body.bytesize}", "", body].join("\n")
    File.write(File.join(out_dir, format("%03d.txt", index)), text)
    summary << "#{format('%03d', index)} #{label} -> #{res.status} #{headers['content-type']} #{body.bytesize}b vary=#{headers['vary'].inspect} loc=#{kept.find { |l| l.start_with?('location') }}"
    index += 1
    res
  rescue Exception => e # rubocop:disable Lint/RescueException
    File.write(File.join(out_dir, format("%03d.txt", index)), "#{label}\nRAISED #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 300]}\n")
    summary << "#{format('%03d', index)} #{label} -> RAISED #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 160]}"
    index += 1
    nil
  end
end

WebhookRequest.where(server_id: server.id).delete_all if server

# signed out: error pages and static files, HEAD and GET, with the Accept headers common clients send
anon = Jar.new
[["HEAD", "/no/such/page", "*/*"], ["HEAD", "/no/such/page", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"],
 ["HEAD", "/no/such/page", nil], ["GET", "/no/such/page", "*/*"], ["GET", "/no/such/page", "application/json"], ["HEAD", "/no/such/page.json", "*/*"],
 ["HEAD", "/login", "*/*"], ["GET", "/login", "text/html"], ["GET", "/login.json", "*/*"], ["GET", "/login", "application/json"],
 ["HEAD", "/assets/nonexistent.css", "*/*"], ["GET", "/404.html", "*/*"], ["HEAD", "/500.html", "*/*"], ["GET", "/robots.txt", "*/*"],
 ["GET", "/raise", "*/*"], ["GET", "/ip", "*/*"], ["GET", "/.well-known/jwks.json", "*/*"], ["GET", "/", "*/*"],
 ["GET", "/org/s4org", "application/json"], ["POST", "/login", "*/*"], ["GET", "/login/reset/nosuchtoken", "*/*"],
 ["GET", "/login?return_to=%2Forg%2Fs4org", "*/*"], ["GET", "/login?a[]=1&a[b]=2", "*/*"], ["GET", "/login?%ff=1", "*/*"], ["GET", "/%ff", "*/*"],
 ["OPTIONS", "/login", "*/*"], ["PROPFIND", "/login", "*/*"]].each do |verb, path, accept|
  opts = accept ? { "HTTP_ACCEPT" => accept } : {}
  step.call(Jar.new, verb, path, opts)
end
step.call(Jar.new, "GET", "/login", "HTTP_HOST" => "evil.example.net")
step.call(Jar.new, "POST", "/login", params: { email_address: "s4@example.com", password: "wrong" })
step.call(Jar.new, "POST", "/api/v1/send/message", "CONTENT_TYPE" => "application/json", input: "{not json")
step.call(Jar.new, "POST", "/api/v1/send/message", "CONTENT_TYPE" => "multipart/form-data; boundary=x", input: "--x\r\nbroken")

# the password reset flow, as a browser does it
ActionMailer::Base.deliveries.clear
reset_page = step.call(anon, "GET", "/login/reset")
rtoken = token_from(reset_page&.body)
step.call(anon, "POST", "/login/reset", params: { authenticity_token: rtoken, email_address: "nobody@example.com" })
step.call(anon, "POST", "/login/reset", params: { authenticity_token: rtoken, email_address: user.email_address, return_to: "/org/s4org" })
stored = User.where(id: user.id).pick(:password_reset_token, :password_reset_token_valid_until)
mail_body = ActionMailer::Base.deliveries.last&.body.to_s
mailed = mail_body[%r{/login/reset/([^\s?]+)}, 1]
reset_mask = ->(b) { b.to_s.gsub(mailed.to_s.empty? ? "\u0000" : mailed, "MAILEDTOKEN") }
reset_facts = ["stored token shape: #{stored[0].to_s.gsub(/[A-Za-z0-9]/, 'x')} (#{stored[0].to_s.size})", "valid for hours: #{stored[1] ? ((stored[1] - Time.now) / 3600).round : nil}",
               "mails sent: #{ActionMailer::Base.deliveries.size}", "mailed token equals stored: #{!mailed.nil? && mailed == stored[0]}",
               "mail link: #{mail_body[%r{\S*/login/reset/\S+}].to_s.gsub(mailed.to_s.empty? ? "\u0000" : mailed, 'MAILEDTOKEN')}",
               "mail subject and from: #{ActionMailer::Base.deliveries.last&.subject} / #{ActionMailer::Base.deliveries.last&.from}"]
step.call(anon, "GET", "/login/reset/#{mailed}?return_to=%2Forg%2Fs4org", mask: reset_mask)
step.call(anon, "POST", "/login/reset/#{mailed}", params: { authenticity_token: rtoken, password: "" }, mask: reset_mask)
step.call(anon, "POST", "/login/reset/#{mailed}", params: { authenticity_token: rtoken, password: "short", password_confirmation: "short" }, mask: reset_mask)
step.call(anon, "POST", "/login/reset/#{mailed}", params: { authenticity_token: rtoken, password: "n3w-passw0rd-s4", password_confirmation: "different" }, mask: reset_mask)
step.call(anon, "POST", "/login/reset/#{mailed}", params: { authenticity_token: rtoken, password: "   ", password_confirmation: "" }, mask: reset_mask)
step.call(anon, "POST", "/login/reset/#{mailed}", params: { authenticity_token: rtoken, password: "n3w-passw0rd-s4", password_confirmation: "n3w-passw0rd-s4", return_to: "/org/s4org" }, mask: reset_mask)
after = User.where(id: user.id).pick(:password_reset_token, :password_reset_token_valid_until)
reset_facts << "after reset, stored token and expiry: #{after.inspect}" << "new password works: #{!!User.find(user.id).authenticate('n3w-passw0rd-s4')}"
step.call(anon, "GET", "/org/s4org")
step.call(Jar.new, "GET", "/login/reset/#{mailed}", mask: reset_mask)
step.call(Jar.new, "POST", "/login/reset/#{mailed}", params: { password: "x" }, mask: reset_mask)
user = User.find(user.id)
user.update!(password: "passw0rd-s4")

# signed in
jar = Jar.new
login_page = step.call(jar, "GET", "/login")
token = token_from(login_page&.body)
step.call(jar, "POST", "/login", params: { authenticity_token: token, email_address: user.email_address, password: "passw0rd-s4" })
home = step.call(jar, "GET", "/")
token = token_from(home&.body) || token
csrf = { "HTTP_X_CSRF_TOKEN" => token.to_s }

base = "/org/s4org/servers/s4server"
gets = ["", "/edit", "/limits", "/retention", "/queue", "/spam", "/delete", "/advanced", "/help/outgoing", "/help/incoming",
        "/messages", "/messages/outgoing", "/messages/incoming", "/messages/held", "/messages/suppressions", "/messages/new",
        "/messages/outgoing?query=to:john@example.com", "/messages/outgoing?query=status:softfail+tag:s4tag",
        "/messages/outgoing?query=before:2026-07-01+after:2026-05-01", "/messages/outgoing?query=nonsense::", "/messages/outgoing?page=2",
        "/domains", "/domains/new", "/credentials", "/credentials/new", "/routes", "/routes/new", "/http_endpoints", "/http_endpoints/new",
        "/smtp_endpoints", "/smtp_endpoints/new", "/address_endpoints", "/address_endpoints/new", "/track_domains", "/track_domains/new",
        "/ip_pool_rules", "/ip_pool_rules/new", "/webhooks", "/webhooks/new", "/webhooks/history"]
{ "domains" => [domain, %w[/setup /verify]], "credentials" => [credential, %w[/edit]], "routes" => [route, %w[/edit]],
  "http_endpoints" => [http_endpoint, %w[/edit]], "webhooks" => [webhook, %w[/edit]] }.each do |name, (record, suffixes)|
  next unless record

  suffixes.each { |s| gets << "/#{name}/#{record.to_param}#{s}" }
  gets << "/#{name}/00000000-0000-4000-8000-ffffffffffff/edit"
end
message_ids.each do |id|
  ["", "/activity", "/plain", "/html", "/html_raw", "/attachments", "/headers", "/deliveries", "/spam_checks", "/download",
   "/attachment?attachment=0"].each { |s| gets << "/messages/#{id}#{s}" }
end
gets << "/messages/999999"
gets.each { |p| step.call(jar, "GET", base + p) }
["/messages/outgoing", "/queue", "/webhooks/history", "/messages/#{message_ids.first}/deliveries", "/credentials", "/domains"].each do |p|
  step.call(jar, "GET", base + p, "HTTP_ACCEPT" => "application/json")
  step.call(jar, "GET", base + p, "HTTP_ACCEPT" => "text/javascript, */*; q=0.01", "HTTP_X_REQUESTED_WITH" => "XMLHttpRequest")
  step.call(jar, "HEAD", base + p)
end
["/", "/settings", "/users", "/users/new", "/users/#{user.to_param}/edit", "/organizations/new", "/ip_pools", "/ip_pools/new",
 "/org/s4org", "/org/s4org/settings", "/org/s4org/delete", "/org/s4org/domains", "/org/s4org/domains/new", "/org/s4org/ip_pool_rules",
 "/org/s4org/ip_pool_rules/new", "/org/s4org/ip_pools", "/org/s4org/servers/new", "/org/s4org/servers/nosuch", "/org/nosuch",
 "/ip_pools/#{ip_pool&.to_param}", "/ip_pools/#{ip_pool&.to_param}/edit", "/ip_pools/#{ip_pool&.to_param}/ip_addresses/new",
 "/.well-known/jwks.json", "/no/such/page", "/login", "/login/reset"].each { |p| step.call(jar, "GET", p) }
step.call(jar, "HEAD", "/no/such/page")
step.call(jar, "HEAD", "/org/s4org/servers/nosuch")

# forms that fail validation, as HTML and as the remote forms send them
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
step.call(jar, "POST", "#{base}/webhooks", params: { webhook: { name: "no csrf" } })
step.call(jar, "PATCH", base, csrf.merge("HTTP_ACCEPT" => "application/json", params: { server: { name: "" } }))
step.call(jar, "PATCH", "/settings", csrf.merge(params: { password: "passw0rd-s4", user: { first_name: "", last_name: "Probe", email_address: user.email_address } }))
step.call(jar, "PATCH", "/settings", csrf.merge(params: { password: "wrong", user: { first_name: "Sfour" } }))
step.call(jar, "POST", "/users", csrf.merge(params: { user: { first_name: "", email_address: "bad", password: "short", password_confirmation: "x" } }))
step.call(jar, "POST", "/org/s4org/servers", csrf.merge("HTTP_ACCEPT" => "application/json", params: { server: { name: "", mode: "Nope", permalink: "bad permalink" } }))
step.call(jar, "POST", "#{base}/messages", csrf.merge(params: { message: { to: "", from: "", subject: "", plain_body: "" } }))
step.call(jar, "POST", "#{base}/messages/#{message_ids.first}/retry", csrf.merge("HTTP_ACCEPT" => "application/json"))
step.call(jar, "DELETE", base, csrf.merge("HTTP_ACCEPT" => "application/json", params: { confirm_text: "wrong" }))
# the IP pool destroy guard (ip_pools_controller.rb:36): the pool has an address and a server
step.call(jar, "DELETE", "/ip_pools/#{ip_pool&.to_param}", csrf)
step.call(jar, "DELETE", "/ip_pools/#{ip_pool&.to_param}", csrf.merge("HTTP_ACCEPT" => "application/json"))
created = step.call(jar, "POST", "#{base}/webhooks", csrf.merge("HTTP_ACCEPT" => "application/json", params: { webhook: { name: "s4 temp", url: "https://example.com/t", all_events: "1", enabled: "1" } }))
temp = server.webhooks.find_by(name: "s4 temp")
summary << "temp webhook created: #{!temp.nil?} #{created&.status}"
step.call(jar, "DELETE", "#{base}/webhooks/#{temp.uuid}", csrf.merge("HTTP_ACCEPT" => "application/json", mask: ->(b) { b.to_s.gsub(temp.uuid, "TEMP") })) if temp
server.webhooks.where(name: "s4 temp").destroy_all
step.call(jar, "POST", "/persist", csrf)
step.call(jar, "DELETE", "/logout", csrf)
step.call(jar, "GET", "/")

# the legacy API
api = lambda do |path, payload, key = "s4fixedkey0000000000000A"|
  mask = lambda do |b|
    b.to_s.gsub(/"id":\d+/, '"id":N').gsub(/"token":"[^"]+"/, '"token":"T"').gsub(/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/, "UUID")
     .gsub(/"timestamp":[0-9.]+/, '"timestamp":N').gsub(/"hold_expiry":[0-9.]+/, '"hold_expiry":N').gsub(/"message_id":"[^"]+"/, '"message_id":"M"')
  end
  step.call(Jar.new, "POST", path, "CONTENT_TYPE" => "application/json", "HTTP_X_SERVER_API_KEY" => key, input: JSON.generate(payload), mask: mask)
end
sent = api.call("/api/v1/send/message", { to: ["john@example.com"], cc: ["cc@example.com"], from: "test@s4.example.com", subject: "s4 api", plain_body: "hi",
                                          html_body: "<p>hi <a href='https://example.com/x?a=1&amp;b=2'>l</a></p>", headers: { "X-S4" => "1" },
                                          attachments: [{ name: "a.txt", content_type: "text/plain", data: "aGk=" }] })
sent_id = begin
  JSON.parse(sent.body).dig("data", "messages", "john@example.com", "id")
rescue StandardError
  nil
end
api.call("/api/v1/send/message", { to: [], from: "test@s4.example.com" })
api.call("/api/v1/send/message", { to: ["john@example.com"], from: "test@unverified.example.net", subject: "x", plain_body: "x" })
api.call("/api/v1/send/message", { to: ["john@example.com"], from: "test@s4.example.com", subject: "x", plain_body: "x" }, "wrongkey")
api.call("/api/v1/send/raw", { mail_from: "test@s4.example.com", rcpt_to: ["raw@example.com"], data: ["Subject: raw\r\nFrom: test@s4.example.com\r\nTo: raw@example.com\r\n\r\nraw body\r\n"].pack("m0") })
api.call("/api/v1/messages/message", { id: sent_id, _expansions: true })
api.call("/api/v1/messages/message", { id: 99_999_999 })
api.call("/api/v1/messages/deliveries", { id: sent_id })
step.call(Jar.new, "GET", "/api/v1/send/message?to[]=a@example.com", "HTTP_X_SERVER_API_KEY" => "s4fixedkey0000000000000A")
step.call(Jar.new, "POST", "/api/v1/send/message", "HTTP_X_SERVER_API_KEY" => "s4fixedkey0000000000000A", params: { to: ["a@example.com"], from: "test@s4.example.com", subject: "form", plain_body: "x" },
          mask: ->(b) { b.to_s.gsub(/"id":\d+/, '"id":N').gsub(/"token":"[^"]+"/, '"token":"T"').gsub(/"message_id":"[^"]+"/, '"message_id":"M"').gsub(/"time":[0-9.e-]+/, '"time":N') })
# leave the queue and the message database as the page walk found them
QueuedMessage.where(server_id: server.id).delete_all if server
WebhookRequest.where(server_id: server.id).delete_all if server
attempt.call("remove api messages") { db.query("DELETE FROM `#{db.database_name}`.`messages` WHERE id > #{message_ids.max.to_i}") } if message_ids.any?

mails = {
  password_reset: -> { u = User.find(user.id); u.password_reset_token = "fixedtokenfixedtokenfixe"; AppMailer.password_reset(u, "/org/s4org") },
  password_reset_plain: -> { u = User.find(user.id); u.password_reset_token = "fixedtokenfixedtokenfixe"; AppMailer.password_reset(u) },
  verify_domain: -> { AppMailer.verify_domain(domain, "admin@s4.example.com", user) },
  server_send_limit_approaching: -> { AppMailer.server_send_limit_approaching(server) },
  server_send_limit_exceeded: -> { AppMailer.server_send_limit_exceeded(server) },
  server_suspended: -> { AppMailer.server_suspended(server) },
  test_message: -> { AppMailer.test_message("to@example.com") }
}.map do |name, build|
  text = begin
    build.call.message.encoded.gsub(/^Message-ID: .*$/, "Message-ID: X").gsub(/^Date: .*$/, "Date: X")
  rescue Exception => e # rubocop:disable Lint/RescueException
    "RAISED #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 200]}"
  end
  "#### #{name}\n#{text}\n"
end
File.write(File.join(out_dir, "mails.txt"), mails.join)

# the lines the suite loads and never runs, and values behind the pages
facts = reset_facts.map { |f| "reset: #{f}" }
fact = lambda do |name, &block|
  facts << "#{name}: #{block.call.inspect[0, 400]}"
rescue Exception => e # rubocop:disable Lint/RescueException
  facts << "#{name}: RAISED #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 200]}"
end
h = ApplicationController.helpers
fact.call("password_reset_token reader is the column") { u = User.find(user.id); u.update_columns(password_reset_token: "abcdefghijklmnopqrstuvwx"); [User.find(user.id).password_reset_token, User.respond_to?(:find_by_password_reset_token), User.find(user.id).respond_to?(:password_reset_token_expires_in)] }
fact.call("begin_password_reset writes the column") { ActionMailer::Base.deliveries.clear; u = User.find(user.id); u.begin_password_reset; r = User.where(id: u.id).pick(:password_reset_token); [r.to_s.size, r == u.password_reset_token, ActionMailer::Base.deliveries.last.body.to_s.include?("/login/reset/#{r}")] }
fact.call("password change clears the token") { u = User.find(user.id); u.update!(password: "passw0rd-s4"); User.where(id: u.id).pick(:password_reset_token, :password_reset_token_valid_until) }
fact.call("authenticate, bad password, previous password first") { u = User.find(user.id); [!!u.authenticate("passw0rd-s4"), u.authenticate("nope"), (User.authenticate("s4@example.com", "nope") rescue $!.message), !!u.authenticate_with_previous_password_first("passw0rd-s4")] }
fact.call("password validations: blank, short, mismatch, spaces") { [["", ""], %w[short short], %w[longenough1 other], ["        ", ""], ["        ", "        "]].map { |p, c| u = User.find(user.id); u.password = p; u.password_confirmation = c; [u.valid?, u.errors.full_messages] } }
fact.call("user json has no secrets beyond before") { User.find(user.id).as_json.keys.sort }
fact.call("migration_waiter.rb:18 wait") { MigrationWaiter.wait; ActiveRecord::Base.connection_pool.migration_context.open.pending_migrations.size }
fact.call("migration_waiter.rb:47 console?") { [MigrationWaiter.console?, MigrationWaiter.rails_command?] }
fact.call("database.rb:333 explain printer") { r = Postal::MessageDB::Database::ResultForExplainPrinter.new(db.query("EXPLAIN SELECT id FROM `#{db.database_name}`.`messages` WHERE id = 1")); ActiveRecord::ConnectionAdapters::MySQL::ExplainPrettyPrinter.new.pp(r, 0.1).lines.map { |l| l.gsub(/\s+/, " ").strip[0, 60] }.values_at(0, 1, -1) }
fact.call("route.rb:122 bad endpoint") { r = server.routes.build(name: "x", domain: domain, _endpoint: "Nope#1", spam_mode: "Mark"); [r.valid?, r.errors.full_messages] }
fact.call("route additional endpoints") { r = server.routes.find(route.id); r.additional_route_endpoints_array = ["HTTPEndpoint#nope"]; [(r.save rescue "#{$!.class}: #{$!.message}"), r.errors.full_messages] }
fact.call("ip pool destroy guard") { (IPPool.find(ip_pool.id).destroy rescue "#{$!.class}") }
fact.call("worker process.rb:105 pool size") { [ActiveRecord::Base.connection_pool.size, ActiveRecord::Base.connection_pool.class.name] }
worker = nil
fact.call("worker process.rb:159 work") { allow = Prometheus::Client::Registry.new; Prometheus::Client.define_singleton_method(:registry) { allow }; worker = Worker::Process.new(thread_count: 1); worker.send(:work, 0) }
fact.call("worker process.rb:217,233 run_tasks") { worker.send(:run_tasks).then { |r| r.is_a?(Array) ? r.size : r } }
fact.call("worker run_tasks again (renewed)") { worker.send(:run_tasks).then { |r| r.is_a?(Array) ? r.size : r } }
fact.call("scheduled tasks recorded") { ScheduledTask.order(:name).pluck(:name).size }
fact.call("worker process.rb:203 release role") { ActiveRecord::Base.connection_pool.with_connection { WorkerRole.release(:tasks) } }
fact.call("retention cutoff provisioner.rb:133") { t = (Time.utc(2026, 6, 1, 3).to_date - 30.days).to_time.end_of_day; [t.class.name, t.utc_offset, t.to_s] }
fact.call("total_size and number helpers") { [db.total_size.class.name, h.number_to_human_size(db.total_size), h.number_with_delimiter(1234567.891), h.number_with_precision(1.005, precision: 2), h.number_to_percentage(12.345, precision: 1), h.number_to_human_size(1536), (h.number_with_delimiter("1e3") rescue $!.class.name), h.number_with_precision(nil, precision: 2)] }
fact.call("times as text") { z = Time.use_zone("London") { Time.zone.at(FIXED.to_f) }; [z.to_fs(:long), z.to_fs(:short), z.to_s, z.as_json, FIXED.as_json, z.to_date.to_fs(:long), "abc_def".humanize, "SoftFail".underscore.humanize] }
fact.call("json encoding") { [{ a: 1.0, b: nil, c: [BigDecimal("1.5"), :sym, FIXED], d: "<&> " }.to_json, ActiveSupport::JSON.decode('{"a":[1,2.5,null]}')] }
fact.call("credential options round trip") { c = server.credentials.find(credential.id); [c.options.class.name, c.options, Credential.type_for_attribute(:options).coder.class.name] }
fact.call("webhook request serialize") do
  w = WebhookRequest.create!(server_id: server.id, webhook_id: webhook.id, url: "https://example.com/hook", event: "MessageSent", uuid: SecureRandom.uuid, payload: { "a" => [1, { "b" => nil }] })
  raw = WebhookRequest.connection.select_value("SELECT payload FROM webhook_requests WHERE id = #{w.id}")
  out = [w.reload.payload, raw]
  w.destroy
  out
end
fact.call("server stats") { [server.queue_size, server.held_messages, server.message_rate.class.name, server.bounce_rate, server.throughput_stats.transform_values { |v| v.class.name }] }
fact.call("message parser tracked link, CGI") { m = db.message(message_ids[1]); [defined?(CGI) ? CGI::VERSION : nil, CGI.unescapeHTML("a&amp;b"), CGI.parse("ssl_mode=TLS&a=1")] }
fact.call("delivery attributes are string keyed") { d = db.message(message_ids.first).deliveries.first; [d.class.name, d.status, d.instance_variable_get(:@attributes).keys.map(&:class).uniq.map(&:name)] }
fact.call("secret key and cookie settings") { c = Rails.application.config; [Rails.application.secret_key_base == Postal::Config.rails.secret_key, c.session_store.name, c.session_options.to_h.transform_values(&:to_s), c.action_dispatch.cookies_same_site_protection.to_s, c.action_dispatch.cookies_serializer, c.active_support.message_serializer.inspect, c.loaded_config_version] }
fact.call("default headers") { Rails.application.config.action_dispatch.default_headers }
fact.call("active record settings") { a = ActiveRecord; [a.default_timezone, a::Base.partial_inserts, a::Base.belongs_to_required_by_default, a::Base.has_many_inversing, a.verify_foreign_keys_for_fixtures, (a.raise_on_assign_to_attr_readonly rescue nil), a::Base.default_column_serializer.inspect, (a.run_after_transaction_callbacks_in_order_defined rescue nil), a::Base.strict_loading_by_default] }
fact.call("active support settings") { s = ActiveSupport; [s.to_time_preserves_timezone, s::JSON::Encoding.use_standard_json_time_format, s::JSON::Encoding.escape_html_entities_in_json, s.utc_to_local_returns_utc_offset_times, (s::Cache.format_version rescue nil), s::KeyGenerator.hash_digest_class.name, s::Digest.hash_digest_class.name, Rails.application.config.active_support.to_h.transform_values { |v| v.is_a?(Class) ? v.name : v }.sort_by { |k, _| k.to_s }] }
fact.call("configured options, every component") { c = Rails.application.config; %i[action_controller action_dispatch action_view action_mailer active_record].map { |k| [k, c.public_send(k).to_h.reject { |_, v| v.is_a?(Proc) || v.is_a?(Hash) || v.is_a?(Array) }.transform_values { |v| v.is_a?(Class) || v.is_a?(Module) ? v.name : (v.is_a?(Pathname) ? "PATH" : v) }.sort_by { |n, _| n.to_s }.map { |n, v| "#{n}=#{v.inspect}" }.join(" ")] } }
fact.call("action controller and view settings") { [ActionController::Base.per_form_csrf_tokens, ActionController::Base.forgery_protection_origin_check, ActionController::Base.raise_on_open_redirects, (ActionController::Base.raise_on_missing_callback_actions rescue nil), ActionView::Helpers::FormTagHelper.default_enforce_utf8, ActionView::Helpers::UrlHelper.button_to_generates_button_tag, (ActionView::Helpers::ContentExfiltrationPreventionHelper.prepend_content_exfiltration_prevention rescue nil), (Rails::HTML::Sanitizer.best_supported_vendor.name rescue nil), ActionView::Helpers::SanitizeHelper.sanitizer_vendor.name, ActionController::Base.wrap_parameters_by_default, Rails.application.config.action_dispatch.use_authenticated_cookie_encryption, Rails.application.config.action_dispatch.use_cookies_with_metadata, (Rails.application.config.action_dispatch.strict_freshness rescue nil), (Rails.application.config.action_dispatch.ignore_leading_brackets.inspect rescue "n/a"), Rails.application.config.action_dispatch.show_exceptions, Rails.application.config.action_dispatch.debug_exception_log_level] }
fact.call("mailer settings") { m = ActionMailer::Base; [m.default_params.except(:from), m.smtp_settings.keys.sort, m.perform_deliveries, m.raise_delivery_errors, (m.smtp_timeout rescue nil), m.default_url_options] }
fact.call("worker process.rb:114 raises the pool size") { w = Worker::Process.allocate; w.instance_variable_set(:@thread_count, 9); w.send(:ensure_connection_pool_size_is_suitable); [ActiveRecord::Base.connection_pool.size, User.count.positive?] }
File.write(File.join(out_dir, "facts.txt"), facts.join("\n") + "\n")

File.write(File.join(out_dir, "summary.txt"), summary.join("\n") + "\n")
File.write(File.join(out_dir, "meta.txt"), "rails #{Rails.version} env #{Rails.env} responses=#{index} deprecations=#{deprecations.uniq.size} messages=#{message_ids.size}\n#{deprecations.uniq.join("\n")}\n#{notes.join("\n")}\n")
