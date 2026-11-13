#!/bin/bash
# Review probe for S1: what the SMTP boot check does when the server stops
# setting the output record separator.
sed -i '46d' app/lib/smtp_server/server.rb
sed -n '44,48p' app/lib/smtp_server/server.rb
( timeout -k 5 90 bundle exec rspec spec/lib/smtp_server/server_spec.rb > /out/probe-e.out 2>&1; echo "rspec exit $?" >> /out/probe-e.out ) &
sleep 45
echo "--- after 45s"
cat /out/probe-e.out
ps -eo pid,etime,args | grep -E "rspec|smtp_server" | grep -v grep
wait
echo "--- at the end"
cat /out/probe-e.out
