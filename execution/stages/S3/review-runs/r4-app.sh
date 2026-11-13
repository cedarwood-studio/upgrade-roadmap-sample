#!/bin/sh
# Fourth review, S3. Runs r4-app.rb on the stage branch (Rails 7.2.4), then on
# the S2 branch (7.1.6) with the 7.2.4 cookies (what a rollback would meet), then
# on the stage branch again with the 7.1.6 cookies (what the deploy meets), and
# prints every difference. The environment comes from the caller.
# Usage: sh /out/r4-app.sh
bundle exec rake db:create db:schema:load > /tmp/setup.txt 2>&1
echo "setup exit=$?"
RAILS_GROUPS=assets bundle exec rake assets:precompile > /tmp/assets.txt 2>&1
echo "assets exit=$?"
S3=$(git rev-parse --abbrev-ref HEAD)

run() { # name, jar
  : > log/production.log 2>/dev/null
  bundle exec ruby /out/r4-app.rb "/tmp/$1" $2 > "/tmp/$1.out" 2>&1
  echo "$1 exit=$? $(cat /tmp/$1/meta.txt 2>/dev/null | head -3 | tr '\n' ' ')"
  tail -2 "/tmp/$1.out" | cut -c1-300
  cp log/production.log "/tmp/$1.rails.log" 2>/dev/null
  sed -E 's/\[[0-9a-f-]{36}\] //; s/[0-9]+(\.[0-9]+)?ms/Nms/g; s/Allocations: [0-9]+/Allocations: N/; s/at [0-9-]+ [0-9:]+ [+-][0-9]+/at T/; s/^[A-Z], \[[^]]+\] +//; s/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f-]{22}/UUID/g; s/authenticity_token"=>"[^"]+"/authenticity_token"=>"X"/' "/tmp/$1.rails.log" > "/tmp/$1.rails.norm" 2>/dev/null
  grep -E '"event":"request"|event=request|\(([0-9]{3})\)' "/tmp/$1.out" | sed -E 's/[0-9]+\.[0-9]+/N/g; s/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f-]{22}/UUID/g; s/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:]+/T/g' > "/tmp/$1.app.norm"
}

run s3
git checkout -q upgrade/s2-remove-the-annotate-blocker
run s2 /tmp/s3/jar.json
git checkout -q "$S3"
run s3b /tmp/s2/jar.json

echo "==== summary on 7.2.4"
cat /tmp/s3/summary.txt
echo "==== summaries, 7.1.6 < > 7.2.4 (first pass of each; cookie replay lines differ by design)"
diff /tmp/s2/summary.txt /tmp/s3b/summary.txt && echo "summaries identical"
echo "==== replay of the other version's cookies"
grep -h "other-version-cookies" /tmp/s2/summary.txt | sed 's/^/on 7.1.6 with 7.2.4 cookies: /'
grep -h "other-version-cookies" /tmp/s3b/summary.txt | sed 's/^/on 7.2.4 with 7.1.6 cookies: /'
echo "==== response files that differ (7.1.6 < > 7.2.4)"
for f in /tmp/s3b/[0-9]*.txt; do
  n=$(basename "$f")
  if ! cmp -s "/tmp/s2/$n" "$f"; then
    echo "--- $n: $(head -1 "$f")"
    diff "/tmp/s2/$n" "$f" | cut -c1-300 | head -16
  fi
done
echo "==== mails (7.1.6 < > 7.2.4)"
diff /tmp/s2/mails.txt /tmp/s3b/mails.txt && echo "mails identical ($(grep -c '^####' /tmp/s3b/mails.txt) mails, $(grep -c RAISED /tmp/s3b/mails.txt) raised)"
grep -A3 RAISED /tmp/s3b/mails.txt | head -20
echo "==== schema dump (7.1.6 < > 7.2.4), then 7.2.4 dump against the committed db/schema.rb"
diff /tmp/s2/schema.rb /tmp/s3b/schema.rb | head -20
diff db/schema.rb /tmp/s3b/schema.rb | head -20
echo "==== settings and middleware (7.1.6 < > 7.2.4)"
diff /tmp/s2/settings.txt /tmp/s3b/settings.txt && echo "settings identical"
tail -22 /tmp/s3b/settings.txt | cut -c1-400
echo "==== Rails log, normalized (7.1.6 < > 7.2.4): $(wc -l < /tmp/s2.rails.norm) and $(wc -l < /tmp/s3b.rails.norm) lines"
diff /tmp/s2.rails.norm /tmp/s3b.rails.norm | cut -c1-260 | head -60
echo "==== sample of the Rails log on 7.2.4"
grep -m3 "Completed" /tmp/s3b.rails.log | cut -c1-260
grep -m3 "Completed" /tmp/s2.rails.log | cut -c1-260
echo "==== application request log lines (7.1.6 < > 7.2.4): $(wc -l < /tmp/s2.app.norm) and $(wc -l < /tmp/s3b.app.norm)"
diff /tmp/s2.app.norm /tmp/s3b.app.norm | cut -c1-300 | head -20
head -2 /tmp/s3b.app.norm | cut -c1-400
echo "==== errors in output"
grep -ciE "NoMethodError|ArgumentError|NameError|deprecat" /tmp/s3.out /tmp/s2.out /tmp/s3b.out
echo "==== end"
