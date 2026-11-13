# frozen_string_literal: true

# What the guard (spec/lib/decidim/frontdoors/guard_spec.rb) expects to find in
# the installed Decidim gems.
module FrontdoorsDecidimFiles
  # decidim-core and decidim-verifications 0.32.2. The layout renders the
  # head before the body tag prints its classes and before the wrapper
  # draws the header; the wrapper draws the breadcrumb bar on every page but
  # the home page unless focus mode is set; the main bar and the footer
  # carry the names the stylesheet hides.
  LINES = {
    "decidim-core" => {
      "app/views/layouts/decidim/_wrapper.html.erb" => [
        '<%= render partial: "layouts/decidim/header/main" %>',
        "<% if !current_user&.ephemeral? && !content_for?(:focus_mode) %>",
        '<%= render partial: "layouts/decidim/header/menu" unless controller_name == "homepage" %>',
        '<%= render partial: "layouts/decidim/footer/main" %>',
        '<%= render partial: "layouts/decidim/footer/mini" %>'
      ],
      "app/views/layouts/decidim/header/_main.html.erb" => [
        '<div id="main-bar" class="main-bar__container">'
      ],
      # The line Deface puts ours in front of.
      "app/views/layouts/decidim/_head.html.erb" => [
        '<%= render partial: "layouts/decidim/head_extra" %>'
      ],
      "app/views/layouts/decidim/_application.html.erb" => [
        '<%= render partial: "layouts/decidim/head" %>',
        '<body class="text-black text-md form-defaults<%= yield (:body_class) %>">',
        '<%= render "layouts/decidim/wrapper" do %>'
      ],
      "app/views/layouts/decidim/application.html.erb" => [
        '<%= render "layouts/decidim/application" do %>'
      ],
      "app/packs/stylesheets/decidim/_layout.scss" => [
        "@apply md:grid grid-cols-12 container grow auto-rows-max;"
      ],
      # Where a module's registered stylesheet lands: at the very end of
      # Decidim's own, outside every layer.
      "app/packs/stylesheets/decidim/application.scss" => [
        '@use "decidim:style-imports[app]" as extra;',
        "@include extra.styles;"
      ],
      # The space's crumb carries the space itself: the trail starts there.
      "app/controllers/concerns/decidim/participatory_space_context.rb" => [
        "resource: current_participatory_space"
      ],
      # The one page Decidim treats as its terms of service: the footer and
      # the sign-up form link to it by this address.
      "app/views/layouts/decidim/footer/_main_legal.html.erb" => [
        'decidim.page_path("terms-of-service")'
      ],
      "app/views/decidim/devise/shared/_tos_fields.html.erb" => [
        'decidim.page_path("terms-of-service")'
      ],
      # Where Decidim sends a new account that has something to verify:
      # after a log-in and after an email confirmation.
      "app/controllers/concerns/decidim/devise_authentication_methods.rb" => [
        "decidim_verifications.onboarding_pending_authorizations_path"
      ],
      "app/controllers/decidim/devise/confirmations_controller.rb" => [
        "return decidim_verifications.onboarding_pending_authorizations_path if pending_onboarding_action?(resource)"
      ],
      "config/routes.rb" => [
        'get "/offline", to: "offline#show"'
      ]
    },
    "decidim-verifications" => {
      # The verifications controller's own pages, and each method that has
      # pages of its own mounted as an engine from Decidim's registry.
      "lib/decidim/verifications/engine.rb" => [
        "resources :authorizations, only: [:new, :create, :index] do",
        "get :onboarding_pending",
        "Decidim.authorization_engines.each do |manifest|",
        'mount manifest.engine, at: "/#{manifest.name}", as: "decidim_#{manifest.name}"' # rubocop:disable Lint/InterpolationCheck
      ],
      "lib/decidim/verifications.rb" => [
        "Decidim::Verifications.workflows.select(&:engine)"
      ],
      # The verification pages are drawn with Decidim's public layout, so
      # the line in its head runs on them.
      "app/views/layouts/decidim/authorizations.html.erb" => [
        '<%= render "layouts/decidim/application" do %>'
      ]
    }
  }.freeze

  # Files a page's band and footer are made of, whole: the head template
  # Deface edits, the breadcrumb bar (the follow button's place in it), its
  # two breadcrumbs (the stylesheet finds "Home" and the first crumb by
  # their place in the desktop one; the mobile one prints the crumb before
  # the last), the helper that builds the list once and keeps it in the
  # view, what prints the list for search engines, and the footer (its legal
  # row is the first of two navs). SHA-256 of each file in decidim-core
  # 0.32.2.
  WHOLE_FILES = {
    "app/views/layouts/decidim/_head.html.erb" => "e463d92fb44d359195038ff14812552fe4b02da3c212f20bce37e5b6a9abcf3d",
    "app/views/layouts/decidim/header/_menu.html.erb" => "8ea03237bcae904326cd6d60bce75792250dd708e88f0fb7ad866339f9b32896",
    "app/views/layouts/decidim/header/_menu_breadcrumb_desktop.html.erb" => "62ca88f8777bea3fdff0873c6acca4fda75e004a28e3bfc8561d43bfc15b20e5",
    "app/views/layouts/decidim/header/_menu_breadcrumb_mobile.html.erb" => "fcf2a3c280b79b1902e8fa32240a2f460c65d4d53516ab591239d4725b227644",
    "app/helpers/decidim/breadcrumb_helper.rb" => "887a495854ba03e559d35865c9059b8871510f848110e33e0424914e18698fda",
    "app/views/layouts/decidim/_schema_org_breadcrumb_list.html.erb" => "49fabb7d8fbc8e4d80b8c78977c10bb9fea212fc0c9efce84f1bb2f2228fce1f",
    "app/serializers/decidim/schema_org_breadcrumb_list_serializer.rb" => "ce99e39148ea2465cc19853ea9557b7039c14f710dbdec1f4d07be1334459c41",
    "app/views/layouts/decidim/footer/_main.html.erb" => "35d59edef6ad9c93148f19c6601e19467bdb6f35c793361471ec39063c04be1f",
    "app/views/layouts/decidim/footer/_mini.html.erb" => "c5dd4fade6cc573ec2979a7d1c1e1c3ad1b2378985a620e5c1e815be81974292"
  }.freeze
end
