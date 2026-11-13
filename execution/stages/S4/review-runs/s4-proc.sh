#!/bin/sh
# Review of S4.
#  1. parameter parsing and cookies on both versions (s4-params.rb), with each version reading the other's cookies
#  2. the three processes started as the Procfile starts them, in production, on 8.0.5.2: web (puma), worker, SMTP server,
#     and the same HEAD and GET requests to the running web process on both versions
#  3. the console and the runner
# Usage: sh /out/s4-proc.sh   (environment from the caller)
S3=upgrade/s3-rails-7-1-6-to-7-2-4
S4=$(git rev-parse --abbrev-ref HEAD)
bundle exec rake db:create db:schema:load > /tmp/setup.txt 2>&1
echo "setup exit=$?"
RAILS_GROUPS=assets bundle exec rake assets:precompile > /tmp/assets.txt 2>&1
echo "assets exit=$?"

echo "==== 1. parameters and cookies"
bundle exec ruby /out/s4-params.rb > /tmp/params-s4.txt 2> /tmp/params-s4.err
C4=$(grep '^COOKIES ' /tmp/params-s4.err | cut -c9-)
git checkout -q $S3
READ_COOKIES="$C4" bundle exec ruby /out/s4-params.rb > /tmp/params-s3.txt 2> /tmp/params-s3.err
C3=$(grep '^COOKIES ' /tmp/params-s3.err | cut -c9-)
git checkout -q "$S4"
READ_COOKIES="$C3" bundle exec ruby /out/s4-params.rb > /tmp/params-s4.txt 2> /tmp/params-s4.err
echo "lines: $(wc -l < /tmp/params-s3.txt) on 7.2.4, $(wc -l < /tmp/params-s4.txt) on 8.0.5.2; raised: $(grep -c RAISED /tmp/params-s3.txt) and $(grep -c RAISED /tmp/params-s4.txt)"
echo "7.2.4 reading 8.0.5.2: $(grep '^cookies written' /tmp/params-s3.txt)"
echo "8.0.5.2 reading 7.2.4: $(grep '^cookies written' /tmp/params-s4.txt)"
echo "-- differences (7.2.4 < > 8.0.5.2)"
grep -v '^cookies written' /tmp/params-s3.txt > /tmp/p3.txt; grep -v '^cookies written' /tmp/params-s4.txt > /tmp/p4.txt
diff /tmp/p3.txt /tmp/p4.txt | cut -c1-330 | head -80 && echo "(end of parameter diff)"
grep -hE "Error|deprecat" /tmp/params-s4.err | head -3 | cut -c1-200

echo "==== 2. processes"
cat > /tmp/client.rb <<'EOF'
require "net/http"
host = ENV.fetch("POSTAL_WEB_HOSTNAME", "postal.example.com")
SKIP = %w[x-request-id x-runtime date etag set-cookie server-timing].freeze
[["HEAD", "/no/such/page", "*/*"], ["HEAD", "/no/such/page", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"], ["HEAD", "/no/such/page", nil],
 ["GET", "/no/such/page", "*/*"], ["HEAD", "/login", "*/*"], ["GET", "/login", "text/html"], ["GET", "/login", nil], ["HEAD", "/assets/nonexistent.css", "*/*"],
 ["HEAD", "/no/such/page.json", "*/*"], ["GET", "/", "*/*"], ["GET", "/ip", "*/*"], ["GET", "/login?a[]=1&a[b]=2", "*/*"], ["HEAD", "/login?a[]=1&a[b]=2", "*/*"],
 ["GET", "/404.html", "*/*"], ["POST", "/api/v1/send/message", "*/*"]].each do |verb, path, accept|
  begin
    http = Net::HTTP.new("127.0.0.1", 5055)
    http.open_timeout = 3
    http.read_timeout = 8
    req = Net::HTTPGenericRequest.new(verb, verb == "POST", verb != "HEAD", path)
    req["Host"] = host
    req["Accept"] = accept if accept
    req.delete("Accept") unless accept
    req.body = "{}" if verb == "POST"
    req["Content-Type"] = "application/json" if verb == "POST"
    res = http.request(req)
    headers = res.each_header.reject { |k, _| SKIP.include?(k) }.sort.map { |k, v| "#{k}=#{v}" }.join("; ")
    puts "#{verb} #{path} Accept=#{accept.inspect} -> #{res.code} | #{headers} | body #{res.body.to_s.bytesize}b"
  rescue StandardError => e
    puts "#{verb} #{path} Accept=#{accept.inspect} -> #{e.class}: #{e.message[0, 120]}"
  end
end
EOF
web() {
  PORT=5055 timeout --preserve-status -s TERM -k 15 22 bundle exec puma -C config/puma.rb > "/tmp/web-$1.txt" 2>&1 &
  pid=$!
  sleep 13
  ruby /tmp/client.rb > "/tmp/head-$1.txt" 2>&1
  wait $pid
  echo "---- web $1: exit=$? $(grep -c . /tmp/head-$1.txt) lines, puma said: $(grep -E "Puma version|Environment|Listening" /tmp/web-$1.txt | tr '\n' ' ' | cut -c1-200)"
  grep -iE "error|deprecat|exception" "/tmp/web-$1.txt" | grep -v '"exception_class":null' | head -4 | cut -c1-240
}
web s4
cat /tmp/head-s4.txt | cut -c1-400
proc() {
  name=$1; shift
  timeout --preserve-status -s TERM -k 10 14 "$@" > "/tmp/$name.txt" 2>&1
  echo "---- $name: exit=$? lines=$(wc -l < /tmp/$name.txt)"
  grep -vE "^No configuration|^Only using" "/tmp/$name.txt" | sed -E 's/"time":"[^"]+"//; s/20[0-9-]+ [0-9:]+ [+-][0-9]+//' | cut -c1-230 | head -7
  echo "  errors: $(grep -ciE "NoMethodError|NameError|ArgumentError|LoadError|deprecat|uninitialized" /tmp/$name.txt)"
  grep -iE "NoMethodError|NameError|ArgumentError|LoadError|deprecat|uninitialized" "/tmp/$name.txt" | head -3 | cut -c1-240
}
proc worker bundle exec ruby script/worker.rb
SMTP_SERVER_DEFAULT_PORT=2525 proc smtp bundle exec ruby script/smtp_server.rb
git checkout -q $S3
web s3
git checkout -q "$S4"
echo "==== web responses (7.2.4 < > 8.0.5.2)"
diff /tmp/head-s3.txt /tmp/head-s4.txt | cut -c1-420 && echo "(end of web diff)"

echo "==== 3. console and runner"
printf 'puts "users=#{User.count} rails=#{Rails.version}"\nputs MigrationWaiter.console?\nexit\n' | bin/rails console 2>&1 | grep -vE "^No configuration|^Only using" | cut -c1-200 | head -8
bin/rails runner 'puts "runner ok #{Rails.version} #{Rails.env} #{User.count}"' 2>&1 | tail -1 | cut -c1-200
bundle exec ruby script/version.rb 2>&1 | tail -1 | cut -c1-100
echo "==== end"
