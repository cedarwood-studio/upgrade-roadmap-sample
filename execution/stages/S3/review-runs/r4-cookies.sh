#!/bin/sh
# Fourth review, S3. Signs in on 7.2.4, replays those cookies on 7.1.6 (what a
# rollback meets), signs in on 7.1.6 and replays those cookies on 7.2.4 (what the
# deploy meets). Sessions are left open (R4_NO_LOGOUT) so the replay is real.
# Also prints the application's own request log lines on both versions.
# Usage: sh /out/r4-cookies.sh
bundle exec rake db:create db:schema:load > /tmp/setup.txt 2>&1
echo "setup exit=$?"
RAILS_GROUPS=assets bundle exec rake assets:precompile > /tmp/assets.txt 2>&1
echo "assets exit=$?"
S3=$(git rev-parse --abbrev-ref HEAD)
export R4_NO_LOGOUT=1
bundle exec ruby /out/r4-app.rb /tmp/s3 > /tmp/s3.out 2>&1
echo "s3 exit=$? $(head -1 /tmp/s3/meta.txt)"
git checkout -q upgrade/s2-remove-the-annotate-blocker
bundle exec ruby /out/r4-app.rb /tmp/s2 /tmp/s3/jar.json > /tmp/s2.out 2>&1
echo "s2 exit=$? $(head -1 /tmp/s2/meta.txt)"
git checkout -q "$S3"
bundle exec ruby /out/r4-app.rb /tmp/s3b /tmp/s2/jar.json > /tmp/s3b.out 2>&1
echo "s3b exit=$? $(head -1 /tmp/s3b/meta.txt)"
echo "==== replay of the other version's cookies"
grep -h "other-version-cookies" /tmp/s2/summary.txt | cut -c1-200 | sed 's/^/on 7.1.6 with 7.2.4 cookies: /'
grep -h "other-version-cookies" /tmp/s3b/summary.txt | cut -c1-200 | sed 's/^/on 7.2.4 with 7.1.6 cookies: /'
echo "==== cookie names in each jar"
cat /tmp/s3/jar.json | tr ',' '\n' | cut -c1-60
echo "==== application log, first lines on each version"
grep -v "^No configuration\|^Only using" /tmp/s3b.out | head -6 | cut -c1-500
echo "--"
grep -v "^No configuration\|^Only using\|warning: Status code" /tmp/s2.out | head -6 | cut -c1-500
echo "==== application log with volatile values masked (7.1.6 < > 7.2.4): $(wc -l < /tmp/s2.out) and $(wc -l < /tmp/s3b.out) lines"
norm() { grep -v "warning: Status code\|^No configuration\|^Only using" "$1" | sed -E 's/[0-9]+\.[0-9]+/N/g; s/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f-]{22}/UUID/g; s/[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9:]+/T/g; s/pid[=:]"?[0-9]+/pid=P/g; s/transaction[=:]"?[0-9a-f]+/transaction=X/g; s/"(view_runtime|db_runtime)":[^,}]+/"\1":N/g; s/(view_runtime|db_runtime)=[^ ]+/\1=N/g; s/CSRF_TOKEN=[^ ]+/CSRF_TOKEN=X/g'; }
norm /tmp/s2.out > /tmp/s2.app
norm /tmp/s3b.out > /tmp/s3b.app
diff /tmp/s2.app /tmp/s3b.app | cut -c1-400 | head -30 && echo "(end of diff)"
echo "==== end"
