#!/bin/sh
# Review of S4. Runs s4-app.rb on the stage branch (Rails 8.0.5.2) to create the
# data, then on the S3 branch (7.2.4), then on the stage branch again, and prints
# every difference between the last two runs, which read the same rows. The Vary
# header, which the stage declares, is counted separately and then left out.
# The environment comes from the caller.
# Usage: sh /out/s4-app.sh
bundle exec rake db:create db:schema:load > /tmp/setup.txt 2>&1
echo "setup exit=$?"
RAILS_GROUPS=assets bundle exec rake assets:precompile > /tmp/assets.txt 2>&1
echo "assets exit=$?"
S4=$(git rev-parse --abbrev-ref HEAD)

run() {
  : > log/production.log 2>/dev/null
  bundle exec ruby /out/s4-app.rb "/tmp/$1" > "/tmp/$1.out" 2>&1
  echo "$1 exit=$? $(cat /tmp/$1/meta.txt 2>/dev/null | tr '\n' ' ' | cut -c1-900)"
  tail -3 "/tmp/$1.out" | cut -c1-300
  cp log/production.log "/tmp/$1.rails.log" 2>/dev/null
  sed -E 's/\[[0-9a-f-]{36}\] //; s/[0-9]+(\.[0-9]+)?ms/Nms/g; s/Allocations: [0-9]+/Allocations: N/; s/at [0-9-]+ [0-9:]+ [+-][0-9]+/at T/; s/^[A-Z], \[[^]]+\] +//; s/authenticity_token"=>"[^"]+"/authenticity_token"=>"X"/; s/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/UUID/g; s#/login/reset/[A-Za-z0-9=_-]+#/login/reset/T#g; s/"token"=>"[^"]+"/"token"=>"T"/; s/[0-9]{10}\.[0-9]+/EPOCH/g' "/tmp/$1.rails.log" > "/tmp/$1.rails.norm" 2>/dev/null
}

run s4
git checkout -q upgrade/s3-rails-7-1-6-to-7-2-4
run s3
git checkout -q "$S4"
run s4b

echo "==== status counts on 8.0.5.2"
sed -E 's/.* -> ([0-9A-Z]+).*/\1/' /tmp/s4b/summary.txt | sort | uniq -c | tr '\n' ' '
echo
echo "==== Vary values, count per version"
echo "7.2.4:   $(sed -E 's/.* vary=("[^"]*"|nil).*/\1/' /tmp/s3/summary.txt | grep -E '^("|nil)' | sort | uniq -c | tr '\n' ' ')"
echo "8.0.5.2: $(sed -E 's/.* vary=("[^"]*"|nil).*/\1/' /tmp/s4b/summary.txt | grep -E '^("|nil)' | sort | uniq -c | tr '\n' ' ')"
echo "==== responses with no Vary on 8.0.5.2"
grep 'vary=nil' /tmp/s4b/summary.txt | cut -c1-110 | head -60
echo "==== responses whose Vary is not the declared value on 8.0.5.2"
grep -v 'vary=nil' /tmp/s4b/summary.txt | grep -v 'vary="Accept, X-Requested-With"' | grep ' -> ' | cut -c1-200 | head -30
echo "==== summaries with Vary left out, 7.2.4 < > 8.0.5.2"
sed -E 's/ vary=("[^"]*"|nil)//' /tmp/s3/summary.txt > /tmp/s3.sum; sed -E 's/ vary=("[^"]*"|nil)//' /tmp/s4b/summary.txt > /tmp/s4b.sum
diff /tmp/s3.sum /tmp/s4b.sum | cut -c1-300 | head -40 && echo "(end of summary diff)"
echo "==== response files that differ beyond the Vary header (7.2.4 < > 8.0.5.2)"
n=0; d=0; v=0
for f in /tmp/s4b/[0-9]*.txt; do
  b=$(basename "$f")
  n=$((n + 1))
  cmp -s "/tmp/s3/$b" "$f" || v=$((v + 1))
  grep -v '^vary: ' "/tmp/s3/$b" > /tmp/a.txt; grep -v '^vary: ' "$f" > /tmp/b.txt
  if ! cmp -s /tmp/a.txt /tmp/b.txt; then
    d=$((d + 1))
    echo "--- $b: $(head -1 "$f" | cut -c1-120)"
    tr ',' '\n' < /tmp/a.txt > /tmp/a2.txt; tr ',' '\n' < /tmp/b.txt > /tmp/b2.txt
    diff /tmp/a2.txt /tmp/b2.txt | cut -c1-400 | head -14
  fi
done
echo "compared $n response files, $v differ at all, $d differ beyond Vary"
echo "==== same version twice (8.0.5.2 first run < > third run), files that differ: noise"
m=0
for f in /tmp/s4b/[0-9]*.txt; do b=$(basename "$f"); cmp -s "/tmp/s4/$b" "$f" || { m=$((m + 1)); echo "noise $b: $(head -1 "$f" | cut -c1-100)"; }; done 2>/dev/null | head -12
echo "==== mails (7.2.4 < > 8.0.5.2)"
diff /tmp/s3/mails.txt /tmp/s4b/mails.txt | head -20 && echo "mails: $(grep -c '^####' /tmp/s4b/mails.txt), raised: $(grep -c RAISED /tmp/s4b/mails.txt)"
echo "==== facts (7.2.4 < > 8.0.5.2)"
tr ' ' '\n' < /tmp/s3/facts.txt > /tmp/f3.txt; tr ' ' '\n' < /tmp/s4b/facts.txt > /tmp/f4.txt
diff /tmp/f3.txt /tmp/f4.txt | cut -c1-300 | head -60 && echo "(end of facts diff)"
echo "==== facts that raised on 8.0.5.2"
grep RAISED /tmp/s4b/facts.txt | cut -c1-300
echo "==== Rails log, normalized (7.2.4 < > 8.0.5.2): $(wc -l < /tmp/s3.rails.norm) and $(wc -l < /tmp/s4b.rails.norm) lines"
diff /tmp/s3.rails.norm /tmp/s4b.rails.norm | cut -c1-260 | head -40
echo "==== Postal's own log on stdout, normalized (7.2.4 < > 8.0.5.2)"
own() {
  grep -vE "^No configuration|^Only using" "/tmp/$1.out" | sed -E 's/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/UUID/g; s/20[0-9]{2}-[0-9]{2}-[0-9]{2}[T ][0-9:.]+( ?[+-][0-9:]+|Z)?/TIME/g; s/[0-9]+\.[0-9]+/F/g; s/\b[0-9a-f]{12,}\b/HEX/g; s#/login/reset/[A-Za-z0-9=_-]+#/login/reset/T#g; s/pid[=:"]+[0-9]+/pid=P/g; s/<[^@ >]+@[^> ]+>/<MID>/g; s/(view_runtime|db_runtime)([=:" ]+)(F|[0-9]+|nil|null)/\1\2R/g' > "/tmp/$1.own"
}
own s3; own s4b
echo "lines: $(wc -l < /tmp/s3.own) and $(wc -l < /tmp/s4b.own); sample:"
grep -m1 "exception_class" /tmp/s4b.own | cut -c1-400
diff /tmp/s3.own /tmp/s4b.own | cut -c1-420 | head -30 && echo "(end of own log diff)"
echo "==== errors in output"
grep -ciE "NoMethodError|ArgumentError|NameError|deprecat" /tmp/s4.out /tmp/s3.out /tmp/s4b.out
grep -hiE "NoMethodError|ArgumentError|NameError|deprecat" /tmp/s4b.out | head -5 | cut -c1-300
echo "==== end"
