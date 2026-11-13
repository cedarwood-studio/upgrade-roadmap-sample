#!/bin/sh
# Review boot check for S3: boot the way a server process does and report the
# exit status and the first lines of any error. Usage: sh /out/boot.sh <label>
label="$1"
bundle exec rake db:create db:schema:load > /tmp/setup.txt 2>&1
echo "[$label] setup exit=$?"
bundle exec ruby -e 'require "./config/environment"; puts "booted rails #{Rails.version} env=#{Rails.env} eager_load=#{Rails.application.config.eager_load}"' > /tmp/boot.txt 2>&1
echo "[$label] boot exit=$?"
grep -v "^	from" /tmp/boot.txt | head -8
