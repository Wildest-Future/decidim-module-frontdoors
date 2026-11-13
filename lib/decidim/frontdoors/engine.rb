# frozen_string_literal: true

require "rails"
require "decidim/core"
require "deface"

module Decidim
  module Frontdoors
    # Frontdoors has no pages, routes, tables or settings of its own. The
    # engine is what brings its three parts into a Decidim application: the
    # one line Deface adds to Decidim's head template
    # (app/overrides/layouts/decidim/_head), the stylesheet (config/assets.rb)
    # and the cookie's two lines in Decidim's cookie notice (config/locales).
    class Engine < ::Rails::Engine
      isolate_namespace Decidim::Frontdoors

      initializer "decidim_frontdoors.shakapacker.assets_path" do
        Decidim.register_assets_path File.expand_path("app/packs", root)
      end
    end
  end
end
