# frozen_string_literal: true

# Review of S4. A deploy moves signed-in users from one version to the other,
# and a rollback moves them back. Signs in on this version and prints the
# cookies and the CSRF token; when READ_JAR is given, first uses the other
# version's cookies and token on this version.
#   bundle exec ruby /out/s4-cookies.rb     (production, fixed secret key)
require "json"
require "rack"
require "rack/mock"
built = Rack::Builder.parse_file(File.expand_path("config.ru", Dir.pwd))
APP = built.is_a?(Array) ? built.first : built
HOST = Postal::Config.postal.web_hostname

def request(cookies, verb, path, opts = {})
  env = { "HTTP_HOST" => HOST }.merge(opts)
  env["HTTP_COOKIE"] = cookies.map { |k, v| "#{k}=#{v}" }.join("; ") unless cookies.empty?
  res = Rack::MockRequest.new(APP).request(verb, path, env)
  Array(res.headers["set-cookie"]).join("\n").split("\n").each do |line|
    name, value = line.split(";").first.to_s.split("=", 2)
    value.to_s.empty? ? cookies.delete(name) : cookies[name] = value
  end
  res
end

user = User.find_by(email_address: "cookie@example.com") ||
       User.create!(first_name: "Cookie", last_name: "Probe", email_address: "cookie@example.com", password: "passw0rd-ck", admin: true)
Organization.find_by(permalink: "ckorg") || Organization.create!(name: "Ck Org", permalink: "ckorg", owner: user)

if ENV["READ_JAR"]
  theirs = JSON.parse(ENV["READ_JAR"])
  cookies = theirs["cookies"]
  home = request(cookies, "GET", "/")
  settings = request(cookies, "GET", "/settings")
  persist = request(cookies, "POST", "/persist", "HTTP_X_CSRF_TOKEN" => theirs["token"])
  patch = request(cookies, "PATCH", "/settings", "HTTP_X_CSRF_TOKEN" => theirs["token"], params: { password: "passw0rd-ck", user: { first_name: "Cookie" } })
  puts "rails #{Rails.version} with cookies from #{theirs['rails']}: GET / #{home.status}, GET /settings #{settings.status} (has address: #{settings.body.include?('cookie@example.com')}), POST /persist with their CSRF token #{persist.status} #{persist.body[0, 10].inspect}, PATCH /settings #{patch.status} #{patch.headers['location']}"
end

cookies = {}
page = request(cookies, "GET", "/login")
token = page.body[/csrf-token" content="([^"]+)/, 1]
login = request(cookies, "POST", "/login", params: { authenticity_token: token, email_address: user.email_address, password: "passw0rd-ck" })
home = request(cookies, "GET", "/")
token = home.body[/csrf-token" content="([^"]+)/, 1]
puts "rails #{Rails.version} own sign-in: POST /login #{login.status}, GET / #{home.status}, cookies #{cookies.keys.sort.join(',')}"
# a request the controller rejects for a missing parameter, for Postal's own log line on stdout
Server.find_by(permalink: "ckserver") || Organization.find_by(permalink: "ckorg").servers.create!(name: "Ck server", mode: "Live", permalink: "ckserver")
missing = request(cookies, "POST", "/org/ckorg/servers/ckserver/domains", "HTTP_X_CSRF_TOKEN" => token)
puts "rails #{Rails.version} POST domains with no parameters: #{missing.status} body #{missing.body.bytesize}b"
warn "JAR #{JSON.generate('rails' => Rails.version, 'cookies' => cookies, 'token' => token)}"
