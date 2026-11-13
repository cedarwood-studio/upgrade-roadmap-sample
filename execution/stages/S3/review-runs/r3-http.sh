#!/bin/sh
# Third review, S3. Sends the same requests through config.ru on the stage branch
# (Rails 7.2.4) and on the S2 branch (Rails 7.1.6) and prints what differs.
# Usage: sh /out/r3-http.sh   (the environment comes from RAILS_ENVIRONMENT)
bundle exec rake db:create db:schema:load > /tmp/setup.txt 2>&1
echo "setup exit=$?"
RAILS_GROUPS=assets bundle exec rake assets:precompile > /tmp/assets.txt 2>&1
echo "assets exit=$?"

bundle exec ruby /out/r3-http.rb /tmp/s3 > /tmp/s3.log 2>&1
echo "s3 run exit=$?"
cat /tmp/s3/meta.txt
cat /tmp/s3/summary.txt
grep -ciE "deprecat" /tmp/s3.log

git checkout -q upgrade/s2-remove-the-annotate-blocker
echo "checked out $(git rev-parse --abbrev-ref HEAD)"
bundle exec ruby /out/r3-http.rb /tmp/s2 > /tmp/s2.log 2>&1
echo "s2 run exit=$?"
cat /tmp/s2/meta.txt
tail -3 /tmp/s2.log | cut -c1-300

echo "==== diff of summaries (7.1.6 < > 7.2.4)"
diff /tmp/s2/summary.txt /tmp/s3/summary.txt && echo "summaries identical"
echo "==== files that differ"
for f in /tmp/s3/[0-9]*.txt; do
  n=$(basename "$f")
  if ! cmp -s "/tmp/s2/$n" "$f"; then
    echo "--- $n: $(head -1 "$f")"
    diff "/tmp/s2/$n" "$f" | cut -c1-400 | head -24
  fi
done
echo "==== end"
