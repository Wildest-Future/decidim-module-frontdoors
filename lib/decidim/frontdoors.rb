# frozen_string_literal: true

require "uri"

require "decidim/frontdoors/version"
require "decidim/frontdoors/engine"

module Decidim
  # Frontdoors: a front door on any page of a space.
  #
  # A link that ends in ?frontdoor=1, to any page inside a participatory space
  # (process, assembly, initiative, conference) or a process group, shows that
  # page without Decidim's navigation: its main bar (logo, search, account,
  # menu), the follow button and the footer's columns are gone, and the
  # breadcrumb bar becomes a thin band that holds a short trail.
  #
  # From 1024 px up the trail starts at the space, wherever the visitor landed:
  # "… › the space › Proposals › an idea", and "…" is the page one step above
  # the space (its process group, its parent assembly, or the page that lists
  # all spaces of its kind). Under 1024 px the page the visitor landed on shows
  # "…" and its own name, where "…" is one step up, and a page below it shows
  # one link to the page one step up, which is Decidim's own phone breadcrumb.
  #
  # The visit stays that way on every page of every space, and on three kinds
  # of page outside them, where the band is one link, "Back": Decidim's log-in
  # pages, its verification pages and its terms of service page. Any other
  # page shows Decidim's full navigation and ends the visit, as does
  # ?frontdoor=0. A page outside a visit is left exactly as Decidim draws it.
  # Decidim's offline page, which its service worker fetches behind the
  # visitor's back, is left out of all of it.
  #
  # The module has three parts:
  #
  #   lib/decidim/frontdoors.rb                                        this file: the rule, the cookie, the trail
  #   app/packs/stylesheets/decidim/frontdoors/frontdoors.scss         what such a page hides and how the band looks
  #   app/overrides/layouts/decidim/_head/frontdoors.html.erb.deface   one line: Decidim::Frontdoors.apply(self)
  #
  # The last one is the only edit to anything of Decidim's: Deface adds that
  # line, which prints nothing, to Decidim's head template. The layout renders
  # the head before it draws the body tag and the header. There we add classes
  # to the body tag (the stylesheet does the hiding) and cut Decidim's own
  # breadcrumb list, in place, down to the trail: the helper breadcrumb_items
  # builds that list once and keeps it in the view, so the breadcrumb bar
  # drawn afterwards prints what we left in it. No Decidim method is replaced
  # and no Decidim template is copied. spec/lib/decidim/frontdoors/guard_spec.rb
  # fails when a Decidim upgrade changes the templates or the helper this
  # relies on.
  #
  # It reads no setting, and the band has no words of its own: "Back" and
  # "Home" are Decidim's.
  module Frontdoors
    # The switch in a link: ?frontdoor=1 starts a visit, ?frontdoor=0 ends one.
    PARAM = "frontdoor"
    COOKIE = "decidim_frontdoors"
    # On the body tag of every page of a visit.
    BODY_CLASS = "frontdoor"
    # Added on the page that starts the trail: under 1024 px the stylesheet then
    # shows "…" and the page's own name instead of Decidim's one link up.
    START_CLASS = "frontdoor-start"
    # Added on a page of a visit outside every space: the band is one link, "Back".
    BACK_CLASS = "frontdoor-back"
    # Trails remembered in one visit; the oldest is dropped.
    MAX_TRAILS = 6
    # Pages of a group of spaces, which have no space of their own: the path of
    # their controller, and the name the group goes by in the cookie.
    GROUP_PAGES = { "decidim/participatory_processes/participatory_process_groups" => "participatory_process_groups" }.freeze
    # The pages outside every space that stay without navigation during a
    # visit. Decidim's log-in family (log-in, sign-up, password, email
    # confirmation, account unlock, invitation, sign-up from a social
    # account): every controller under this path.
    LOG_IN_PAGES = "decidim/devise/"
    # Its verification pages. This controller draws the "verify your account"
    # page a new account is sent to, the list of a participant's
    # verifications, and the form of a verification method that is one form.
    # A method with pages of its own (identity documents, a code by post or
    # by SMS, a census, or one from another module) is an engine in Decidim's
    # registry of verification methods (Decidim.authorization_engines): a
    # page that engine's routes led to is one of them.
    VERIFICATION_PAGES = "decidim/verifications/authorizations"
    # And its terms of service page, which signing up links to: the page its
    # pages controller shows for the one address Decidim itself names
    # (Decidim::StaticPage::DEFAULT_PAGES), not the other help pages.
    STATIC_PAGES = "decidim/pages"
    # Decidim's "you are offline" page (the route /offline). Its service worker
    # fetches it once, behind the visitor's back, to show when the network is
    # gone: it never starts, changes or ends a visit, and never loses its
    # navigation.
    OFFLINE_PAGE = "decidim/offline"
    # What a remembered start looks like: a path on this site, never "//host".
    ADDRESS = %r{\A/[^/\\\s]\S{0,500}\z}

    # Where a page is. kind is :inside (a space or a process group, named by
    # key, such as "assemblies/some-slug"), :kept (outside every space, and
    # without navigation during a visit: a log-in page, a verification page,
    # the terms of service) or :outside (any other page: full navigation, and
    # the end of a visit).
    Place = Struct.new(:kind, :key)

    # on: is this page shown without navigation? trails: what to remember,
    # newest first, each a pair of key and the address its trail starts at
    # ([] forgets the visit). start: which of the page's crumbs starts the
    # trail. back: on a page of a visit outside every space, the address
    # "Back" leads to.
    Decision = Struct.new(:on, :trails, :start, :back)

    class << self
      # The whole rule, with nothing of Rails in it.
      #
      # param:  "1", "0" or nil, from the address.
      # trails: what the cookie remembers ([] when no visit is on).
      # place:  where the page is.
      # crumbs: for a page inside a space, the address of each crumb of Decidim's
      #         breadcrumb, top to bottom, without the language. The last one
      #         stands for the page itself.
      def decide(param:, trails:, place:, crumbs: [])
        return off if param == "0" || place.kind == :outside
        return Decision.new(on: trails.any?, trails:, back: trails.first&.last) if place.kind == :kept
        return off unless param == "1" || trails.any?

        start = start_among(crumbs, trails, place.key) unless param == "1"
        return Decision.new(on: true, trails:, start:) if start

        start_here(trails, place.key, crumbs)
      end

      # Called from Decidim's head template with the view, on every public page.
      def apply(view)
        param = view.params[PARAM].presence_in(%w(0 1))
        raw = view.cookies[COOKIE]
        return if param.nil? && raw.nil? # no such link and no visit: nothing of ours happens
        return if view.controller_path == OFFLINE_PAGE

        trails = read(view, raw)
        place = place_of(view)
        decision = decide(param:, trails:, place:, crumbs: place.kind == :inside ? addresses(view) : [])
        remember(view, decision.trails, trails, raw) unless prefetch?(view.request)
        draw(view, decision, place) if decision.on && !drawn_by_decidim?(view)
        nil
      end

      private

      def off
        Decision.new(on: false, trails: [])
      end

      # Landed here, or reached a page that is not under the start of its trail:
      # the trail starts here now, and is the newest.
      def start_here(trails, key, crumbs)
        others = trails.reject { |trail_key, _| trail_key == key }
        Decision.new(on: true, trails: [[key, crumbs.last], *others].first(MAX_TRAILS), start: [crumbs.size - 1, 0].max)
      end

      # Every page drawn with the layout counts as opened by a person, whoever
      # fetched it. Once Decidim's service worker is installed it fetches every
      # page the visitor opens, and the browser then marks the request as not a
      # document (Sec-Fetch-Dest: empty), so what those headers say is not read.
      # The one page the worker fetches on its own, the offline page, is left
      # out in apply. The other exception: a page the browser loads ahead of a
      # click, and says so (Sec-Purpose: prefetch), is drawn and remembers
      # nothing.
      def prefetch?(request)
        request.headers["Sec-Purpose"].present?
      end

      # Budget voting has switched Decidim's own focus mode on, and a visitor
      # with a temporary session gets Decidim's bare header: on those pages
      # there is no breadcrumb bar, and the main bar holds the only way out.
      # They are left as Decidim draws them; the visit goes on.
      def drawn_by_decidim?(view)
        view.content_for?(:focus_mode) || view.try(:current_user).try(:ephemeral?)
      end

      def draw(view, decision, place)
        classes = place.kind == :inside ? cut(view, decision.start) : lead_back(view, decision.back)
        view.content_for(:body_class, " #{[BODY_CLASS, *classes].join(" ")}")
      end

      # The start of this page's trail: the newest remembered trail that belongs
      # to the page's own space or starts at one of the crumbs above it (its
      # process group, a parent assembly). nil when the page is not under it.
      def start_among(crumbs, trails, key)
        _, start = trails.find { |trail_key, address| trail_key == key || crumbs.include?(address) }
        crumbs.rindex(start) if start
      end

      def place_of(view)
        space = view.try(:current_participatory_space)
        return Place.new(kind: :inside, key: "#{space.manifest.name}/#{space.slug}") if space

        group = GROUP_PAGES[view.controller_path]
        return Place.new(kind: :inside, key: "#{group}/#{view.params[:id]}") if group

        Place.new(kind: kept_outside_a_space?(view) ? :kept : :outside)
      end

      def kept_outside_a_space?(view)
        view.controller_path.start_with?(LOG_IN_PAGES) ||
          (view.controller_path == STATIC_PAGES && Decidim::StaticPage::DEFAULT_PAGES.include?(view.params[:id].to_s)) ||
          view.controller_path == VERIFICATION_PAGES || verification_method?(view.request)
      end

      # Is this one of a verification method's own pages? Decidim keeps a
      # registry of the methods that have pages of their own, its own and
      # those other modules add, each with the engine that draws them; the
      # request remembers the routes of the engine that led to this page.
      # Without decidim-verifications there is no registry and no such page.
      def verification_method?(request)
        methods = Decidim.try(:authorization_engines)
        return false if methods.blank?

        routes = request.try(:routes)
        routes.present? && methods.any? { |method| method.engine.routes.equal?(routes) }
      end

      # The address of each crumb of Decidim's own list for this page, without
      # the empty items its templates skip. The list itself is not touched here.
      def addresses(view)
        languages = I18n.available_locales.map { |locale| Regexp.escape(locale.to_s) }.join("|")
        here = address(view.request.path, languages)
        found = view.breadcrumb_items.compact_blank.map { |item| address(item[:url], languages) }
        found[-1] ||= here unless found.empty? # a last crumb with no link is the page itself
        found.presence || [here]
      end

      # An address as it is compared and remembered: the path only, without the
      # language (/en/...) and without a closing slash.
      def address(url, languages)
        path = URI.parse(url.to_s).path.to_s.sub(%r{\A/(?:#{languages})(?=/|\z)}, "").chomp("/")
        path.presence
      rescue URI::InvalidURIError
        nil
      end

      # A page inside a space. Removes from Decidim's list, the very array its
      # templates will read, everything above the crumb that sits just above
      # the space (on a process group's page, above the group). That crumb
      # stays: from 1024 px up the stylesheet shows it as "…", and its link
      # carries ?frontdoor=1. With nothing above the space in Decidim's list,
      # "…" is the home page. start is the crumb the visitor's trail starts
      # at; when it is the page itself, the stylesheet shows, under 1024 px,
      # the crumb before the last as "…", so that link carries ?frontdoor=1
      # too.
      def cut(view, start)
        items = view.breadcrumb_items
        items.reject!(&:blank?)
        only_start = start >= items.size - 1
        from = top_of_the_trail(view, items)
        items.shift(from - 1) if from > 1
        items.unshift(label: I18n.t("decidim.menu.home"), url: view.decidim.root_path, active: false) if from.zero? || items.empty?
        [0, (-2 if only_start)].compact.each { |at| items[at] = items[at].merge(url: with_the_switch(items[at][:url])) }
        only_start ? [START_CLASS] : []
      end

      # The space's own crumb, which Decidim marks with the space itself; on a
      # process group's page, the page's crumb.
      def top_of_the_trail(view, items)
        space = view.try(:current_participatory_space)
        (space && items.index { |item| item[:resource] == space }) || [items.size - 1, 0].max
      end

      # A page of a visit outside every space (a log-in page, a verification
      # page, the terms of service): the band holds one link, Decidim's own
      # word "Back", to the start of the newest trail.
      def lead_back(view, back)
        language = "/#{I18n.locale}"
        back = "#{language}#{back}" if view.request.path.start_with?("#{language}/")
        view.breadcrumb_items.replace([{ label: I18n.t("layouts.decidim.header.back"), url: back, active: false }])
        [BACK_CLASS]
      end

      def with_the_switch(url)
        uri = URI.parse(url.to_s)
        others = URI.decode_www_form(uri.query.to_s).reject { |pair| pair.first == PARAM }
        uri.query = URI.encode_www_form(others << [PARAM, "1"])
        uri.to_s
      rescue URI::InvalidURIError, ArgumentError
        url
      end

      # The cookie is signed: a value we did not write reads as nothing, and is
      # then forgotten. It ends with the browser session.
      def read(view, raw)
        return [] if raw.nil?

        value = view.cookies.signed[COOKIE]
        well_formed = value.is_a?(Array) && value.size.between?(1, MAX_TRAILS) &&
                      value.all? { |pair| pair.is_a?(Array) && pair.size == 2 && pair.all?(String) && pair.last.match?(ADDRESS) }
        well_formed ? value : []
      end

      def remember(view, trails, before, raw)
        if trails.empty?
          view.cookies.delete(COOKIE) unless raw.nil?
        elsif trails != before
          view.cookies.signed[COOKIE] = { value: trails, httponly: true, same_site: :lax, secure: view.request.ssl? }
        end
      end
    end
  end
end
