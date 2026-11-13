# frozen_string_literal: true

# Review of S4. Action Pack 8.0 parses request parameters itself instead of
# handing them to Rack (changelog: "Maintain Rack 2 parameter parsing
# behaviour"). The application ran Rack 3 on 7.2.4, so this prints how each
# version parses a set of ordinary and odd inputs, for diff.
#   bundle exec ruby /out/s4-params.rb > file
require "./config/environment"
require "rack/mock"
require "json"

show = lambda do |label, env|
  req = ActionDispatch::Request.new(env)
  out = begin
    JSON.generate(req.params.except("controller", "action"))
  rescue Exception => e # rubocop:disable Lint/RescueException
    "RAISED #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 120]}"
  end
  puts "#{label} => #{out}"
end

queries = ["a=1&b=2", "a=1&a=2", "a[]=1&a[]=2", "a[b]=1&a[c]=2", "a[b][]=1&a[b][]=2", "a[][b]=1&a[][c]=2&a[][b]=3", "a[0]=x&a[1]=y",
           "to[]=a@example.com&to[]=b@example.com&headers[X-A]=1&attachments[][name]=a.txt&attachments[][data]=aGk%3D&attachments[][name]=b.txt",
           "[a]=1", "[]=1", "a[=1", "a]=1", "a[b]c=1", "a[b]c[d]=1", "a[]b=1", "a[b=1", "a[[b]]=1", "x[y]=1&x=2", "x=2&x[y]=1", "x[]=1&x[y]=2",
           "=1", "&&", "a", "a=", "a&b", "a=1;b=2", "a=1&;b=2", "a+b=c+d", "a%20b=c%2Bd", "a=%E2%9C%93", "utf8=%E2%9C%93&q=x", "a=%ff", "%ff=1",
           "a%5Bb%5D=1", "a%5B%5D=1&a%5B%5D=2", "a=1%00", "a%00=1", "a[b][c][d][e][f][g][h]=1", "a.b=1", "a-b=1", "page=2&query=status:softfail+tag:x",
           "a[][]=1", "a[][][b]=1", "a[b][][c]=1&a[b][][c]=2", "a[b][][c]=1&a[b][][d]=2", "return_to=%2Forg%2Facme", "a==1", "a=b=c", "a[ b ]=1",
           "#{(['a'] * 40).join('[') + (']' * 39)}=1", "#{'x[]=1&' * 30}y=1", "_method=delete", "id[]=", "id[]", "ids[]=&ids[]=1", "a[b]=&a[c]", "a=1&a[]=2", "a[]=2&a=1"]
queries.each { |q| show.call("GET ?#{q[0, 70]}", Rack::MockRequest.env_for("/x?#{q}")) }
queries.each { |q| show.call("POST form #{q[0, 70]}", Rack::MockRequest.env_for("/x", method: "POST", input: q, "CONTENT_TYPE" => "application/x-www-form-urlencoded")) }

['{"a":1}', '{"a":[]}', '{"a":[null]}', '{"a":[null,1]}', '{"a":null}', '{"a":{"b":[]}}', "[1,2]", '[{"a":1}]', '"str"', "1", "null", "", "{not json",
 '{"to":["a@example.com"],"headers":{"X":"1"},"attachments":[{"name":"a","data":"aGk="}],"bounce":false}', '{"a":1,"a":2}', '{"a":1.0e3,"b":true}'].each do |body|
  show.call("POST json #{body[0, 70]}", Rack::MockRequest.env_for("/x", method: "POST", input: body, "CONTENT_TYPE" => "application/json"))
end

multipart = lambda do |parts|
  parts.map { |name, value, file| "--BOUND\r\nContent-Disposition: form-data; name=\"#{name}\"#{file ? "; filename=\"#{file}\"\r\nContent-Type: text/plain" : ''}\r\n\r\n#{value}\r\n" }.join + "--BOUND--\r\n"
end
[[%w[a 1], %w[b 2]], [["a[]", "1"], ["a[]", "2"]], [["f", "data", "x.txt"]], [["a[b]", "1"], ["a[c]", "data", "y.txt"]], [["[a]", "1"]], [["a[b]c", "1"]]].each do |parts|
  req = ActionDispatch::Request.new(Rack::MockRequest.env_for("/x", method: "POST", input: multipart.call(parts), "CONTENT_TYPE" => "multipart/form-data; boundary=BOUND"))
  out = begin
    req.params.except("controller", "action").to_h.inspect.gsub(/#<[^>]+>/) { |m| m[/#<([A-Za-z:]+)/, 1] }[0, 200]
  rescue Exception => e # rubocop:disable Lint/RescueException
    "RAISED #{e.class}: #{e.message.to_s.lines.first.to_s.strip[0, 120]}"
  end
  puts "POST multipart #{parts.map(&:first).join(',')} => #{out}"
end

# cookies and the session, read back by the other version: written to /tmp/cookie-<version>.txt by the caller
jar = ActionDispatch::Request.new(Rack::MockRequest.env_for("/")).cookie_jar
jar.signed[:s] = { value: "signed-value", httponly: true }
jar.encrypted[:e] = { value: "encrypted-value" }
jar.signed[:h] = { value: { "a" => [1, nil, "x"] } }
warn "COOKIES #{JSON.generate(jar.instance_variable_get(:@set_cookies).transform_values { |v| v[:value] })}"
if ENV["READ_COOKIES"]
  theirs = JSON.parse(ENV["READ_COOKIES"])
  req = ActionDispatch::Request.new(Rack::MockRequest.env_for("/", "HTTP_COOKIE" => theirs.map { |k, v| "#{k}=#{Rack::Utils.escape(v)}" }.join("; ")))
  puts "cookies written by the other version read as: #{[req.cookie_jar.signed[:s], req.cookie_jar.encrypted[:e], req.cookie_jar.signed[:h]].inspect}"
end
