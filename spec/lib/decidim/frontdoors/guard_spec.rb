# frozen_string_literal: true

require "spec_helper"
require "digest"

# A guard on Decidim, and on the module's own bounds.
#
# Frontdoors replaces no Decidim method and copies no Decidim template: Deface
# adds one line to Decidim's head template, and everything else relies on how
# Decidim itself draws a page. It relies on where the layout renders the head,
# on when it draws the breadcrumb bar, on the markup of that bar (the
# stylesheet picks crumbs out of it by their place), on the helper that builds
# the list once and keeps it, and on how Decidim names its log-in pages, its
# verification pages, its terms of service page and its offline page. When an
# upgrade changes one of those, an example here fails and somebody has to
# look, before a page silently shows the wrong trail or gets its navigation
# back.
module Decidim
  describe Frontdoors do
    include FrontdoorsStandIns

    let(:core) { "decidim-core" }
    let(:root) { Decidim::Frontdoors::Engine.root }
    let(:head) { "app/views/layouts/decidim/_head.html.erb" }
    let(:our_line) { "<% Decidim::Frontdoors.apply(self) %>" }
    let(:what_to_do) do
      "Read the new file, open a space with ?frontdoor=1 at 390 and 1366 px (script/walk), " \
        "and bring lib/decidim/frontdoors.rb, the stylesheet and this spec up to date."
    end

    describe "Decidim's templates" do
      FrontdoorsDecidimFiles::LINES.each do |gem_name, files|
        files.each do |file, expected|
          it "still has the lines the module relies on in #{gem_name}, #{file}" do
            source = decidim_file(gem_name, file)

            expected.each do |line|
              expect(source).to include(line), "Decidim changed #{file}: this line is gone.\n  #{line}\n#{what_to_do}"
            end
          end
        end
      end

      it "renders the head before the body tag and before the wrapper" do
        file = "app/views/layouts/decidim/_application.html.erb"
        source = decidim_file(core, file)
        head_at, body_at, wrapper_at = FrontdoorsDecidimFiles::LINES.fetch(core).fetch(file).map { |line| source.index(line) }

        expect(head_at).to be < body_at, "the head must be rendered before the body tag prints its classes"
        expect(body_at).to be < wrapper_at, "the head must be rendered before the wrapper draws the breadcrumb bar"
      end

      FrontdoorsDecidimFiles::WHOLE_FILES.each do |file, digest|
        it "has not changed #{file}" do
          expect(Digest::SHA256.hexdigest(decidim_file(core, file))).to eq(digest), "Decidim changed #{file}.\n#{what_to_do} Then record the new checksum here."
        end
      end

      it "builds the breadcrumb list once and keeps it in the view" do
        expect(Decidim::BreadcrumbHelper.method_defined?(:breadcrumb_items)).to be(true)
        expect(decidim_file(core, "app/helpers/decidim/breadcrumb_helper.rb")).to include("@breadcrumb_items ||= [].tap do |items|")
      end

      it "still switches focus mode on in budget voting's own pages" do
        %w(
          app/views/decidim/budgets/projects/index.html.erb
          app/views/decidim/budgets/projects/show.html.erb
          app/views/decidim/budgets/orders/status.html.erb
        ).each do |file|
          expect(decidim_file("decidim-budgets", file)).to include("<% content_for :focus_mode, true %>"),
                                                           "#{file} no longer sets focus mode itself: check that budget voting is still left alone"
        end
      end
    end

    describe "the one line Deface adds" do
      let(:override_file) { root.join("app/overrides/layouts/decidim/_head/frontdoors.html.erb.deface") }
      let(:overrides) { Deface::Override.find(virtual_path: "layouts/decidim/_head") }
      let(:source) { decidim_file(core, head) }
      let(:edited) { Deface::Override.apply(source.dup, { virtual_path: "layouts/decidim/_head" }) }

      # Deface's instruction and the code share one line. With the code on a
      # line of its own, Deface puts a line break in front of it, and every
      # page of the site comes out one byte longer.
      it "is the module's only override, and one line of code" do
        instruction = %(<!-- insert_before "erb[loud]:contains('layouts/decidim/head_extra')" original "1573380893c34669dfbbf12e5116c3f951a7a815" -->)

        expect(Dir[root.join("app/overrides/**/*")].select { |path| File.file?(path) }).to eq([override_file.to_s])
        expect(override_file.read).to eq("#{instruction}#{our_line}\n")
      end

      it "is known to Deface as an edit of Decidim's head template, and of nothing else" do
        ours = Deface::Override.all.values.flat_map(&:values).select { |override| override.source.to_s.include?("Decidim::Frontdoors") }

        expect(ours.size).to eq(1)
        expect(ours.first.args[:virtual_path]).to eq("layouts/decidim/_head")
        expect(overrides).to include(ours.first)
      end

      it "still applies: the line is in the template once, before the application's own head content" do
        expect(source).not_to include("Decidim::Frontdoors")
        expect(edited.scan("Decidim::Frontdoors.apply(self)").size).to eq(1), "Deface no longer finds the place in Decidim's head template. #{what_to_do}"
        expect(edited.index(our_line)).to be < edited.index('<%= render partial: "layouts/decidim/head_extra" %>')
      end

      # Deface takes the template apart and puts it together again. What
      # comes out must be Decidim's file with our line in it, and no other
      # byte changed: a page outside a visit is then drawn exactly as before.
      it "changes nothing else in the template, not even a line break" do
        expect(edited.sub("#{our_line}\n", "")).to eq(source)
        expect(edited.bytesize - source.bytesize).to eq(our_line.bytesize + 1)
      end
    end

    describe "the pages the rule knows by Decidim's names for them" do
      it "still finds the log-in family under one path" do
        [Decidim::Devise::SessionsController, Decidim::Devise::RegistrationsController, Decidim::Devise::PasswordsController,
         Decidim::Devise::ConfirmationsController, Decidim::Devise::UnlocksController, Decidim::Devise::InvitationsController,
         Decidim::Devise::OmniauthRegistrationsController].each do |controller|
          expect(controller.controller_path).to start_with(described_class::LOG_IN_PAGES), controller.name
        end
      end

      it "still finds the terms of service page, the process group page and the offline page" do
        expect(Decidim::PagesController.controller_path).to eq(described_class::STATIC_PAGES)
        expect(Decidim::StaticPage::DEFAULT_PAGES).to eq(%w(terms-of-service))
        expect([Decidim::ParticipatoryProcesses::ParticipatoryProcessGroupsController.controller_path]).to eq(described_class::GROUP_PAGES.keys)
        expect(Decidim::OfflineController.controller_path).to eq(described_class::OFFLINE_PAGE)
      end

      it "still finds the four kinds of space" do
        expect(Decidim.participatory_space_manifests.map { |manifest| manifest.name.to_s }.sort).to eq(%w(assemblies conferences initiatives participatory_processes))
      end

      it "still finds Decidim's verification pages" do
        controller = Decidim::Verifications::AuthorizationsController

        expect(controller.controller_path).to eq(described_class::VERIFICATION_PAGES)
        expect(controller.action_methods).to include("index", "new", "create", "onboarding_pending")
      end

      it "still finds each verification method's own pages through Decidim's registry" do
        methods = Decidim.authorization_engines

        expect(methods.map(&:name)).to include("id_documents", "postal_letter", "csv_census", "sms")
        methods.each do |method|
          expect(method.engine).to be < Rails::Engine, method.name
          expect(method.engine.routes).to be_a(ActionDispatch::Routing::RouteSet), method.name
        end
        [Decidim::Verifications::IdDocuments::AuthorizationsController, Decidim::Verifications::PostalLetter::AuthorizationsController,
         Decidim::Verifications::CsvCensus::AuthorizationsController, Decidim::Verifications::Sms::AuthorizationsController].each do |controller|
          expect(controller.ancestors).to include(Decidim::ApplicationController), "#{controller.name} is no longer drawn with Decidim's public layout"
        end
      end

      # A request keeps the routes of the engine that led to its page: that is
      # how a verification method's pages are told from any other page.
      it "still finds the engine that led to a page in the request" do
        expect(ActionDispatch::Request.instance_method(:routes)).to be_present
        expect(Rails::Engine.instance_method(:build_request).source_location.first).to include("railties")
      end
    end

    # The offline page is the only page Decidim's service worker fetches on its
    # own; every other page it fetches is one the visitor opened. If an upgrade
    # makes it fetch another page by itself, that page would start or end a
    # visit behind the visitor's back.
    it "still has a service worker that fetches no page of its own but the offline page" do
      worker = decidim_file(core, "app/packs/src/decidim/sw/sw.js")

      expect(Digest::SHA256.hexdigest(worker)[0, 12]).to eq("a110fb37a27f"),
                                                         "Decidim's service worker changed: check which pages it fetches without the visitor, then update this checksum"
      expect(worker).to include('offlineFallback({ pageFallback: "/offline" });')
    end

    describe "the module's own bounds" do
      let(:stylesheet) { root.join("app/packs/stylesheets/decidim/frontdoors/frontdoors.scss") }
      let(:cookie_strings) { %w(description service) }

      it "is made of these files and no others: no page, table, setting, admin screen or script" do
        files = Dir.chdir(root) { Dir["{app,config,db,lib}/**/*"].select { |path| File.file?(path) } }.sort

        expect(files).to eq(%w(
                              app/overrides/layouts/decidim/_head/frontdoors.html.erb.deface
                              app/packs/stylesheets/decidim/frontdoors/frontdoors.scss
                              config/assets.rb
                              config/locales/ca.yml
                              config/locales/en.yml
                              config/locales/es.yml
                              lib/decidim/frontdoors.rb
                              lib/decidim/frontdoors/engine.rb
                              lib/decidim/frontdoors/version.rb
                            ))
        expect(Decidim::Frontdoors::Engine.routes.routes.to_a).to be_empty
      end

      it "registers its stylesheet with Decidim, and no script" do
        assets = root.join("config/assets.rb").read

        expect(assets).to include('Decidim::Shakapacker.register_stylesheet_import("stylesheets/decidim/frontdoors/frontdoors")')
        expect(assets).not_to include("register_entrypoints")
        expect(Decidim::Shakapacker.configuration.stylesheet_imports.dig("imports", "app")).to include("stylesheets/decidim/frontdoors/frontdoors")
      end

      it "has one stylesheet with no color of its own, every rule of it for a page of a visit" do
        styles = stylesheet.read.gsub(%r{//.*$}, "")

        expect(styles).not_to match(/#[0-9a-f]{3,8}\b|rgb\(|hsl\(/i), "colors come from Decidim's theme (its secondary color, its white and grey, by name)"
        expect(styles.lines.grep(/^\S.*\{\s*$/).map(&:strip)).to eq(["@mixin frontdoor-dots {", "body.frontdoor {"]), "every rule sits inside body.frontdoor"
      end

      it "has no words of its own but the cookie's two lines in Decidim's cookie notice" do
        %w(en es ca).each do |locale|
          words = YAML.load_file(root.join("config/locales/#{locale}.yml"))

          expect(words.keys).to eq([locale])
          items = words.dig(locale, "layouts", "decidim", "data_consent", "details", "items")
          expect(words).to eq({ locale => { "layouts" => { "decidim" => { "data_consent" => { "details" => { "items" => items } } } } } })
          expect(items.keys).to eq([described_class::COOKIE])
          expect(items.fetch(described_class::COOKIE).keys.sort).to eq(cookie_strings)
          cookie_strings.each do |string|
            expect(I18n.t("layouts.decidim.data_consent.details.items.#{described_class::COOKIE}.#{string}", locale:)).to be_present
          end
        end
      end

      it "leaves Decidim's own words as they are" do
        expect(I18n.t("layouts.decidim.header.back", locale: :en)).to eq("Back")
        expect(I18n.t("layouts.decidim.header.back", locale: :es)).to eq("Atrás")
        expect(I18n.t("layouts.decidim.header.back", locale: :ca)).to eq("Enrere")
        expect(I18n.t("decidim.menu.home", locale: :en)).to eq("Home")
      end

      it "lists its cookie in the essential group of Decidim's cookie notice, once" do
        essential = Decidim.consent_categories.find { |category| category[:slug] == "essential" }

        expect(essential[:items].count { |item| item == { type: "cookie", name: described_class::COOKIE } }).to eq(1)
        expect(essential[:items].pluck(:name)).to include("_session_id", Decidim.consent_cookie_name)
      end

      it "is for Decidim 0.32 from 0.32.2 on" do
        expect(described_class.version).to eq("0.1.0")
        expect(described_class::COMPAT_DECIDIM_VERSION).to eq([">= 0.32.2", "< 0.33"])
        expect(Gem::Requirement.new(*described_class::COMPAT_DECIDIM_VERSION)).to be_satisfied_by(Gem::Version.new(Decidim.version))
      end
    end
  end
end
