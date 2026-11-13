# frozen_string_literal: true

require "rails"
require "decidim/core"
require "deface"

module Decidim
  module Frontdoors
    # Frontdoors has no pages, routes, tables or settings of its own. The
    # engine is what brings its parts into a Decidim application: the one
    # line Deface adds to Decidim's head template
    # (app/overrides/layouts/decidim/_head), the stylesheet (config/assets.rb)
    # and the cookie's entry in Decidim's cookie notice (below, and its two
    # strings in config/locales).
    class Engine < ::Rails::Engine
      isolate_namespace Decidim::Frontdoors

      initializer "decidim_frontdoors.shakapacker.assets_path" do
        Decidim.register_assets_path File.expand_path("app/packs", root)
      end

      # The cookie is listed with the ones a site cannot work without, beside
      # Decidim's session cookie. After the application's own initializers,
      # so that a list the application has set for itself gets it too.
      config.after_initialize do
        essential = Decidim.consent_categories.find { |category| category[:slug] == "essential" }
        if essential
          essential[:items] ||= []
          listed = essential[:items].any? { |item| item[:name] == Decidim::Frontdoors::COOKIE }
          essential[:items] << { type: "cookie", name: Decidim::Frontdoors::COOKIE } unless listed
        end
      end
    end
  end
end
