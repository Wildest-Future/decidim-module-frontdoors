# frozen_string_literal: true

# The requests of script/production_check, made as a visitor's browser would
# make them, against the test application booted in production mode.
require "net/http"

BASE = URI(ARGV.fetch(0, "http://127.0.0.1:3044"))
PAGE = "/en/processes/production-check"
OWN_BODY = '<body class="text-black text-md form-defaults">'
OUR_BODY = '<body class="text-black text-md form-defaults frontdoor frontdoor-start">'

def get(path, cookie: nil)
  request = Net::HTTP::Get.new(path)
  request["Cookie"] = cookie if cookie
  request["X-Forwarded-Proto"] = "https" # as behind a proxy: a production Decidim sends plain http to https
  Net::HTTP.start(BASE.host, BASE.port, read_timeout: 120) { |http| http.request(request) }
end

def check(what, passed)
  abort "FAILED: #{what}" unless passed
  puts "  #{what}"
end

90.times do
  break if begin
    get("/up").code == "200"
  rescue StandardError
    false
  end

  sleep 1
end
up = get("/up")
abort "FAILED: /up answered #{up.code} #{up["location"]} #{up.body.to_s[0, 300].gsub(/\s+/, " ")}" unless up.code == "200"

plain = get(PAGE)
puts "GET #{PAGE} -> #{plain.code}"
check "Decidim's own body tag", plain.body.include?(OWN_BODY)
# The cookie notice's dialog is part of every page, and our cookie has a row
# in it. Nothing else of ours is in a page outside a visit.
ours_in_page = plain.body.scan("frontdoor").size
check "nothing of ours in the page but the cookie's row in the cookie notice", ours_in_page == 1 && plain.body.include?("<td>decidim_frontdoors</td>")
check("no cookie of ours", plain.get_fields("set-cookie").to_a.none? { |cookie| cookie.start_with?("decidim_frontdoors") })

door = get("#{PAGE}?frontdoor=1")
puts "GET #{PAGE}?frontdoor=1 -> #{door.code}"
ours = door.get_fields("set-cookie").to_a.find { |cookie| cookie.start_with?("decidim_frontdoors=") }
check "body classes frontdoor frontdoor-start", door.body.include?(OUR_BODY)
check "our cookie, HttpOnly, with no expiry date", ours.to_s.match?(/httponly/i) && !ours.to_s.match?(/expires|max-age/i)
check "the trail's first crumb is the list of processes, with the switch", door.body.include?('href="/en/processes?frontdoor=1"')

again = get(PAGE, cookie: ours.to_s.split(";").first)
puts "GET #{PAGE} with the cookie alone -> #{again.code}"
check "still without navigation", again.body.include?(OUR_BODY)

sheet = door.body[%r{/decidim-packs/css/decidim_core-[0-9a-f]+\.css}]
abort "FAILED: no fingerprinted decidim_core stylesheet in the page" unless sheet
rules = get(sheet).body.scan("body.frontdoor").size
puts "GET #{sheet} -> #{get(sheet).code}"
check "#{rules} of our rules in Decidim's compiled stylesheet", rules.positive?
puts "PASSED"
