#!/bin/sh
# Review of S4. Session cookies across the deploy and the rollback, and
# Postal's own request log line for a rejected request, on both versions.
# Usage: sh /out/s4-cookies.sh   (production, fixed secret key, LOGGING_ENABLED=true)
S3=upgrade/s3-rails-7-1-6-to-7-2-4
S4=$(git rev-parse --abbrev-ref HEAD)
bundle exec rake db:create db:schema:load > /tmp/setup.txt 2>&1
echo "setup exit=$?"
RAILS_GROUPS=assets bundle exec rake assets:precompile > /tmp/assets.txt 2>&1
echo "assets exit=$?"
git checkout -q $S3
bundle exec ruby /out/s4-cookies.rb > /tmp/ck-s3.txt 2> /tmp/ck-s3.err
J3=$(grep '^JAR ' /tmp/ck-s3.err | cut -c5-)
git checkout -q "$S4"
READ_JAR="$J3" bundle exec ruby /out/s4-cookies.rb > /tmp/ck-s4.txt 2> /tmp/ck-s4.err
J4=$(grep '^JAR ' /tmp/ck-s4.err | cut -c5-)
git checkout -q $S3
READ_JAR="$J4" bundle exec ruby /out/s4-cookies.rb > /tmp/ck-s3b.txt 2> /tmp/ck-s3b.err
git checkout -q "$S4"
echo "==== deploy: 8.0.5.2 reads a 7.2.4 session"
grep '^rails ' /tmp/ck-s4.txt | cut -c1-330
echo "==== rollback: 7.2.4 reads an 8.0.5.2 session"
grep '^rails ' /tmp/ck-s3b.txt | cut -c1-330
grep -hE "Error" /tmp/ck-s3.err /tmp/ck-s4.err /tmp/ck-s3b.err | head -4 | cut -c1-240
echo "==== Postal's own log, lines for requests that raised (7.2.4, then 8.0.5.2)"
norm() { grep -E "exception_class\"?[:=]\"?[A-Z]" "$1" | sed -E 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/UUID/g; s/20[0-9]{2}-[0-9]{2}-[0-9]{2}[T ][0-9:.]+( ?[+-][0-9:]+|Z)?/TIME/g; s/[0-9]+\.[0-9]+/F/g; s/\b[0-9a-f]{12,}\b/HEX/g; s#/cache/bundle/ruby/[0-9.]+/gems/([a-z]+)-[0-9.]+/#GEM/\1/#g; s/:[0-9]+:in /:N:in /g' | cut -c1-900; }
norm /tmp/ck-s3.txt > /tmp/own3.txt; norm /tmp/ck-s4.txt > /tmp/own4.txt
echo "lines: $(wc -l < /tmp/own3.txt) and $(wc -l < /tmp/own4.txt); all log lines: $(grep -vc '^rails ' /tmp/ck-s3.txt) and $(grep -vc '^rails ' /tmp/ck-s4.txt)"
head -1 /tmp/own3.txt
head -1 /tmp/own4.txt
echo "==== all own log lines, normalized, diff (7.2.4 first run < > 8.0.5.2)"
all() { grep -v '^rails ' "$1" | grep -vE "^No configuration|^Only using" | sed -E 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/UUID/g; s/20[0-9]{2}-[0-9]{2}-[0-9]{2}[T ][0-9:.]+( ?[+-][0-9:]+|Z)?/TIME/g; s/[0-9]+\.[0-9]+/F/g; s/\b[0-9a-f]{12,}\b/HEX/g; s/(runtime[=:" ]+)(F|[0-9]+|nil|null)/\1R/g; s/pid[=:"]+[0-9]+/pid=P/g'; }
all /tmp/ck-s3.txt > /tmp/all3.txt; all /tmp/ck-s3b.txt | tail -n "$(wc -l < /tmp/all3.txt)" > /tmp/all3b.txt; all /tmp/ck-s4.txt | tail -n "$(wc -l < /tmp/all3.txt)" > /tmp/all4.txt
diff /tmp/all3.txt /tmp/all4.txt | cut -c1-500 | head -16 && echo "(end of own log diff)"
echo "==== end"
