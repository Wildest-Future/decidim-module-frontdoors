# frozen_string_literal: true

require "decidim/dev/common_rake"

desc "Generates a dummy app for testing"
task test_app: "decidim:generate_external_test_app"

# Decidim's generator writes port 3000 into the development application, as
# the port its emails and its own redirects point to. compose.yaml serves it
# at another port, so that it does not clash with an application already
# running at 3000: the port is written into the generated file afterwards.
DEVELOPMENT_APP_PORT = ENV.fetch("DEVELOPMENT_APP_PORT", "3033")

desc "Generates a development app."
task development_app: "decidim:generate_external_development_app" do
  file = File.expand_path("development_app/config/environments/development.rb", __dir__)
  File.write(file, File.read(file).gsub("port: 3000", "port: #{DEVELOPMENT_APP_PORT}"))
end
