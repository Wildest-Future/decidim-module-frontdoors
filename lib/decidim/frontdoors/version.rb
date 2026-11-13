# frozen_string_literal: true

module Decidim
  # This holds the decidim-frontdoors version.
  module Frontdoors
    # The versions of Decidim this release was built and checked on.
    COMPAT_DECIDIM_VERSION = [">= 0.32.2", "< 0.33"].freeze

    def self.version
      "0.1.0"
    end
  end
end
