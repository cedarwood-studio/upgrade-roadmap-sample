#!/bin/sh
# Fifth review, S3. Runs r5-app.rb on the stage branch (Rails 7.2.4) to create
# the data, then on the S2 branch (7.1.6), then on the stage branch again, and
# prints every difference between the last two runs, which read the same rows.
# The environment comes from the caller.
# Usage: sh /out/r5-app.sh
bundle exec rake db:create db:schema:load > /tmp/setup.txt 2>&1
echo "setup exit=$?"
RAILS_GROUPS=assets bundle exec rake assets:precompile > /tmp/assets.txt 2>&1
echo "assets exit=$?"
S3=$(git rev-parse --abbrev-ref HEAD)

run() {
  : > log/production.log 2>/dev/null
  bundle exec ruby /out/r5-app.rb "/tmp/$1" > "/tmp/$1.out" 2>&1
  echo "$1 exit=$? $(cat /tmp/$1/meta.txt 2>/dev/null | tr '\n' ' ' | cut -c1-900)"
  tail -3 "/tmp/$1.out" | cut -c1-300
  cp log/production.log "/tmp/$1.rails.log" 2>/dev/null
  sed -E 's/\[[0-9a-f-]{36}\] //; s/[0-9]+(\.[0-9]+)?ms/Nms/g; s/Allocations: [0-9]+/Allocations: N/; s/at [0-9-]+ [0-9:]+ [+-][0-9]+/at T/; s/^[A-Z], \[[^]]+\] +//; s/authenticity_token"=>"[^"]+"/authenticity_token"=>"X"/; s/ \([0-9]+ quer(y|ies), [0-9]+ cached\)//; s/GC: Nms/TAIL/; s/Allocations: N/TAIL/; s/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/UUID/g' "/tmp/$1.rails.log" > "/tmp/$1.rails.norm" 2>/dev/null
}

run s3
git checkout -q upgrade/s2-remove-the-annotate-blocker
run s2
git checkout -q "$S3"
run s3b

echo "==== summary on 7.2.4 (third run)"
cut -c1-150 /tmp/s3b/summary.txt | sed -e 's#/org/r5org/servers/r5server#~#' -e 's#text/html; charset=utf-8#html#' -e 's#application/json; charset=utf-8#json#'
echo "==== status counts on 7.2.4"
sed -E 's/.* -> ([0-9A-Z]+).*/\1/' /tmp/s3b/summary.txt | sort | uniq -c | tr '\n' ' '
echo
echo "==== summaries, 7.1.6 < > 7.2.4"
diff /tmp/s2/summary.txt /tmp/s3b/summary.txt | cut -c1-300 | head -40 && echo "(end of summary diff)"
echo "==== response files that differ (7.1.6 < > 7.2.4)"
n=0; d=0
for f in /tmp/s3b/[0-9]*.txt; do
  b=$(basename "$f")
  n=$((n + 1))
  if ! cmp -s "/tmp/s2/$b" "$f"; then
    d=$((d + 1))
    echo "--- $b: $(head -1 "$f")"
    tr ',' '\n' < "/tmp/s2/$b" > /tmp/a.txt; tr ',' '\n' < "$f" > /tmp/b.txt
    diff /tmp/a.txt /tmp/b.txt | cut -c1-400 | head -14
  fi
done
echo "compared $n response files, $d differ"
echo "==== mails (7.1.6 < > 7.2.4)"
diff /tmp/s2/mails.txt /tmp/s3b/mails.txt | head -20 && echo "mails: $(grep -c '^####' /tmp/s3b/mails.txt), raised: $(grep -c RAISED /tmp/s3b/mails.txt)"
echo "==== facts (7.1.6 < > 7.2.4)"
diff /tmp/s2/facts.txt /tmp/s3b/facts.txt | cut -c1-400 && echo "(end of facts diff)"
cut -c1-330 /tmp/s3b/facts.txt
echo "==== Rails log, normalized with the declared Completed/Rendered difference masked (7.1.6 < > 7.2.4): $(wc -l < /tmp/s2.rails.norm) and $(wc -l < /tmp/s3b.rails.norm) lines"
diff /tmp/s2.rails.norm /tmp/s3b.rails.norm | cut -c1-260 | head -40
echo "==== errors in output"
grep -ciE "NoMethodError|ArgumentError|NameError|deprecat" /tmp/s3.out /tmp/s2.out /tmp/s3b.out
grep -hiE "NoMethodError|ArgumentError|NameError|deprecat" /tmp/s3b.out | head -5 | cut -c1-300
echo "==== end"
