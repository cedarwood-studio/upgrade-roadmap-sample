#!/bin/sh
# Third review, S3. Starts puma in production on the stage branch (Rails 7.2.4)
# and then on the S2 branch (Rails 7.1.6) and prints the status line and the
# headers each sends for HEAD and GET requests to error pages, as a client sees them.
# Usage: sh /out/r3-head.sh
bundle exec rake db:create db:schema:load > /tmp/setup.txt 2>&1
echo "setup exit=$?"
RAILS_GROUPS=assets bundle exec rake assets:precompile > /tmp/assets.txt 2>&1
echo "assets exit=$?"

one() {
  PORT=5055 timeout --preserve-status -s TERM -k 15 20 bundle exec puma -C config/puma.rb > "/tmp/web-$1.txt" 2>&1 &
  pid=$!
  sleep 12
  ruby /out/r3-head-client.rb > "/tmp/head-$1.txt" 2>&1
  wait $pid
  echo "---- $1: $(grep -c . /tmp/head-$1.txt) lines, puma said: $(grep -E "Puma version|Environment" /tmp/web-$1.txt | tr '\n' ' ')"
  bundle exec ruby -e 'puts "rails " + Gem.loaded_specs["rails"].version.to_s' 2>/dev/null
  cat "/tmp/head-$1.txt"
}

one s3
git checkout -q upgrade/s2-remove-the-annotate-blocker
one s2
echo "==== diff (7.1.6 < > 7.2.4)"
diff /tmp/head-s2.txt /tmp/head-s3.txt && echo "identical"
