#!/bin/sh
# Fourth review, S3. Compares the installed framework source for 7.1.6 and 7.2.4
# in the places where a difference reaches a user of this application without
# any application line changing: translated messages, time zone names, MIME
# types, the error responses, the request log line, secure password.
# Usage: sh /out/r4-gemdiff.sh
G=/cache/bundle/ruby/3.4.0/gems
d() {
  echo "==== $1"
  diff -u "$G/$2" "$G/$3" | cut -c1-220 | head -"${4:-60}"
  echo "(exit of diff above is not shown; empty means identical)"
}
for c in activemodel activerecord activesupport actionview; do
  for f in $(cd $G/$c-7.2.4 && find lib -name "en.yml"); do
    d "$c $f" "$c-7.1.6/$f" "$c-7.2.4/$f"
  done
done
d "time zone names" activesupport-7.1.6/lib/active_support/values/time_zone.rb activesupport-7.2.4/lib/active_support/values/time_zone.rb 40
d "mime types" actionpack-7.1.6/lib/action_dispatch/http/mime_types.rb actionpack-7.2.4/lib/action_dispatch/http/mime_types.rb
d "public exceptions" actionpack-7.1.6/lib/action_dispatch/middleware/public_exceptions.rb actionpack-7.2.4/lib/action_dispatch/middleware/public_exceptions.rb 80
d "exception wrapper" actionpack-7.1.6/lib/action_dispatch/middleware/exception_wrapper.rb actionpack-7.2.4/lib/action_dispatch/middleware/exception_wrapper.rb 120
d "show exceptions" actionpack-7.1.6/lib/action_dispatch/middleware/show_exceptions.rb actionpack-7.2.4/lib/action_dispatch/middleware/show_exceptions.rb 80
d "host authorization" actionpack-7.1.6/lib/action_dispatch/middleware/host_authorization.rb actionpack-7.2.4/lib/action_dispatch/middleware/host_authorization.rb 80
d "action dispatch railtie" actionpack-7.1.6/lib/action_dispatch/railtie.rb actionpack-7.2.4/lib/action_dispatch/railtie.rb 80
d "controller log subscriber" actionpack-7.1.6/lib/action_controller/log_subscriber.rb actionpack-7.2.4/lib/action_controller/log_subscriber.rb 80
d "active record controller runtime" activerecord-7.1.6/lib/active_record/railties/controller_runtime.rb activerecord-7.2.4/lib/active_record/railties/controller_runtime.rb 80
d "secure password" activemodel-7.1.6/lib/active_model/secure_password.rb activemodel-7.2.4/lib/active_model/secure_password.rb 80
d "request forgery protection" actionpack-7.1.6/lib/action_controller/metal/request_forgery_protection.rb actionpack-7.2.4/lib/action_controller/metal/request_forgery_protection.rb 120
d "mime type parse" actionpack-7.1.6/lib/action_dispatch/http/mime_type.rb actionpack-7.2.4/lib/action_dispatch/http/mime_type.rb 80
d "request (http method)" actionpack-7.1.6/lib/action_dispatch/http/request.rb actionpack-7.2.4/lib/action_dispatch/http/request.rb 120
d "rack logger" railties-7.1.6/lib/rails/rack/logger.rb railties-7.2.4/lib/rails/rack/logger.rb 80
d "default middleware stack" railties-7.1.6/lib/rails/application/default_middleware_stack.rb railties-7.2.4/lib/rails/application/default_middleware_stack.rb 80
d "cookies" actionpack-7.1.6/lib/action_dispatch/middleware/cookies.rb actionpack-7.2.4/lib/action_dispatch/middleware/cookies.rb 80
d "static" actionpack-7.1.6/lib/action_dispatch/middleware/static.rb actionpack-7.2.4/lib/action_dispatch/middleware/static.rb 60
d "redirecting" actionpack-7.1.6/lib/action_controller/metal/redirecting.rb actionpack-7.2.4/lib/action_controller/metal/redirecting.rb 100
d "number converter" activesupport-7.1.6/lib/active_support/number_helper/number_converter.rb activesupport-7.2.4/lib/active_support/number_helper/number_converter.rb 60
d "inflector humanize" activesupport-7.1.6/lib/active_support/inflector/methods.rb activesupport-7.2.4/lib/active_support/inflector/methods.rb 60
