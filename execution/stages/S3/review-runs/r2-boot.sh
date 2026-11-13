#!/bin/sh
# Second review boot check for S3: boot the way a server process does and report
# the exit status and the first lines of any error. Usage: sh /out/r2-boot.sh <label> [noschema]
label="$1"
if [ "$2" = "noschema" ]; then
  bundle exec rake db:create > /tmp/setup.txt 2>&1
else
  bundle exec rake db:create db:schema:load > /tmp/setup.txt 2>&1
fi
echo "[$label] setup exit=$?"
bundle exec ruby -e 'require "./config/environment"; puts "booted rails #{Rails.version} env=#{Rails.env} eager_load=#{Rails.application.config.eager_load} key_from_credentials=#{Rails.application.secret_key_base == Rails.application.credentials.secret_key_base} local_secret_file=#{File.exist?("tmp/local_secret.txt")} routes=#{Rails.application.routes.routes.size}"' > /tmp/boot.txt 2>&1
echo "[$label] boot exit=$?"
grep -v "^	from" /tmp/boot.txt | head -8
