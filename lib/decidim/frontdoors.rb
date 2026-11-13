# frozen_string_literal: true

require "decidim/frontdoors/version"
require "decidim/frontdoors/engine"

module Decidim
  # Step 2 only: the smallest thing that shows where the hook runs. The rule
  # replaces it in step 3.
  module Frontdoors
    def self.apply(view)
      return unless view.params[:frontdoor] == "1"

      view.breadcrumb_items.shift
      view.content_for(:body_class, " frontdoor")
      nil
    end
  end
end
