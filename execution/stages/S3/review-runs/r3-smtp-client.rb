# frozen_string_literal: true

# Third review, S3. A short SMTP conversation with the running SMTP server on
# loopback. The MAIL FROM and RCPT TO commands make the server query the main
# database from its event loop.
require "socket"
require "timeout"

def say(sock, line)
  sock.write("#{line}\r\n")
  reply = +""
  loop do
    part = sock.gets.to_s
    reply << part
    break unless part =~ /\A\d{3}-/
  end
  puts "C: #{line}  S: #{reply.strip.tr("\r\n", ' |')[0, 200]}"
end

begin
  Timeout.timeout(8) do
    sock = begin
      TCPSocket.new("127.0.0.1", 2525)
    rescue StandardError
      TCPSocket.new("::1", 2525)
    end
    puts "S: #{sock.gets.to_s.strip}"
    say(sock, "EHLO r3.example.com")
    say(sock, "MAIL FROM:<sender@example.com>")
    say(sock, "RCPT TO:<nobody@unknown-domain.example.org>")
    say(sock, "AUTH PLAIN AHVzZXIAd3Jvbmc=")
    say(sock, "NOOP")
    say(sock, "QUIT")
    sock.close
  end
rescue StandardError, Timeout::Error => e
  puts "smtp client: #{e.class}: #{e.message}"
end

begin
  require "net/http"
  r = Net::HTTP.get_response(URI("http://127.0.0.1:9091/health"))
  puts "smtp health: #{r.code} #{r.body.to_s[0, 60]}"
rescue StandardError => e
  puts "smtp health: #{e.class} #{e.message}"
end
