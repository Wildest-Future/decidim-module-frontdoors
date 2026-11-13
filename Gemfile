# frozen_string_literal: true

source "https://rubygems.org"

ruby RUBY_VERSION

gem "decidim", "0.32.2"
# Two kinds of space that are not in the decidim gem itself. Frontdoors works
# in both, so the test and development applications carry them.
gem "decidim-conferences", "0.32.2"
gem "decidim-frontdoors", path: "."
gem "decidim-initiatives", "0.32.2"

gem "bootsnap", "~> 1.3"
gem "puma", ">= 6.3.1"

group :development, :test do
  gem "byebug", "~> 11.0", platform: :mri

  gem "decidim-dev", "0.32.2"
end

group :development do
  gem "faker", "~> 3.2"
  gem "letter_opener_web", "~> 2.0"
  gem "listen", "~> 3.1"
  gem "web-console", "~> 4.2"
end
