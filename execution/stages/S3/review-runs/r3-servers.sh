#!/bin/sh
# Third review, S3. Starts the three server processes the way Procfile.dev does,
# talks to each over loopback, stops them with TERM and reports.
# Usage: sh /out/r3-servers.sh
bundle exec rake db:create db:schema:load > /tmp/setup.txt 2>&1
echo "setup exit=$?"

echo "==== worker (script/worker.rb), 14 seconds, then TERM"
timeout --preserve-status -s TERM -k 15 14 bundle exec ruby script/worker.rb > /tmp/worker.txt 2>&1 &
wpid=$!
sleep 9
ruby -rnet/http -e 'begin; r = Net::HTTP.get_response(URI("http://127.0.0.1:9090/health")); puts "worker health: #{r.code} #{r.body.to_s[0,60]}"; rescue => e; puts "worker health: #{e.class} #{e.message}"; end'
wait $wpid
echo "worker exit=$?"
echo "worker lines=$(wc -l < /tmp/worker.txt) errors=$(grep -ciE "error|exception|undefined|deprecat" /tmp/worker.txt)"
grep -iE "error|exception|undefined|deprecat" /tmp/worker.txt | cut -c1-300 | head -10
head -12 /tmp/worker.txt | cut -c1-220
tail -6 /tmp/worker.txt | cut -c1-220

echo "==== smtp server (script/smtp_server.rb) on port 2525, then TERM"
timeout --preserve-status -s TERM -k 15 16 bundle exec ruby script/smtp_server.rb > /tmp/smtp.txt 2>&1 &
spid=$!
sleep 9
ruby /out/r3-smtp-client.rb
wait $spid
echo "smtp exit=$?"
echo "smtp lines=$(wc -l < /tmp/smtp.txt) errors=$(grep -ciE "exception|undefined|deprecat|NoMethod" /tmp/smtp.txt)"
grep -iE "exception|undefined|deprecat|NoMethod" /tmp/smtp.txt | cut -c1-300 | head -10
head -8 /tmp/smtp.txt | cut -c1-220
tail -5 /tmp/smtp.txt | cut -c1-220

echo "==== web server (puma -C config/puma.rb) on port 5055, then TERM"
RAILS_GROUPS=assets bundle exec rake assets:precompile > /tmp/assets.txt 2>&1
echo "assets exit=$?"
PORT=5055 timeout --preserve-status -s TERM -k 15 22 bundle exec puma -C config/puma.rb > /tmp/web.txt 2>&1 &
ppid=$!
sleep 13
ruby /out/r3-web-client.rb
wait $ppid
echo "web exit=$?"
echo "web lines=$(wc -l < /tmp/web.txt) errors=$(grep -ciE "exception|undefined|deprecat|NoMethod" /tmp/web.txt)"
grep -iE "exception|undefined|deprecat|NoMethod" /tmp/web.txt | cut -c1-300 | head -10
head -14 /tmp/web.txt | cut -c1-220
