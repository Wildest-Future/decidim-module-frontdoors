# frozen_string_literal: true

require "spec_helper"

# Two things are checked here, neither of which draws a page:
#
# 1. The rule itself (Decidim::Frontdoors.decide): where ?frontdoor=1 works
#    and where it does nothing, where a visitor's trail starts, which pages
#    stay without navigation, what ends a visit.
# 2. What Decidim::Frontdoors.apply does to a page, with a stand-in for the
#    page (spec/shared/frontdoors_stand_ins.rb): what is left of Decidim's
#    breadcrumb list (the trail from the space down, what "…" is, "Back"
#    outside a space), the classes on the body tag, the cookie, and that a
#    page outside a visit is not touched.
#
# The guard on Decidim is in spec/lib/decidim/frontdoors/guard_spec.rb, and
# real pages are drawn in spec/system.
module Decidim
  describe Frontdoors do
    include FrontdoorsStandIns

    let(:process) { FrontdoorsStandIns::PROCESS }
    let(:assembly) { FrontdoorsStandIns::ASSEMBLY }
    let(:group) { FrontdoorsStandIns::GROUP }
    let(:listing) { FrontdoorsStandIns::LISTING }
    let(:group_page) { FrontdoorsStandIns::GROUP_PAGE }
    let(:front) { FrontdoorsStandIns::FRONT }
    let(:list) { FrontdoorsStandIns::LIST }
    let(:idea) { FrontdoorsStandIns::IDEA }
    let(:other_idea) { FrontdoorsStandIns::OTHER_IDEA }
    let(:front_crumbs) { FrontdoorsStandIns::FRONT_CRUMBS }
    let(:list_crumbs) { FrontdoorsStandIns::LIST_CRUMBS }
    let(:idea_crumbs) { FrontdoorsStandIns::IDEA_CRUMBS }
    let(:process_space) { FrontdoorsStandIns::PROCESS_SPACE }
    let(:back) { " frontdoor frontdoor-back" }

    it "has the names decided for it" do
      expect(described_class::PARAM).to eq("frontdoor")
      expect(described_class::COOKIE).to eq("decidim_frontdoors")
      expect([described_class::BODY_CLASS, described_class::START_CLASS, described_class::BACK_CLASS]).to eq(%w(frontdoor frontdoor-start frontdoor-back))
    end

    describe ".decide" do
      it "starts a trail at the page when ?frontdoor=1 is on a page inside a space" do
        { front_crumbs => 2, list_crumbs => 3, idea_crumbs => 4 }.each do |crumbs, last|
          decision = decide(param: "1", trails: [], place: inside(process), crumbs:)

          expect(decision.on).to be(true)
          expect(decision.trails).to eq([[process, crumbs.last]])
          expect(decision.start).to eq(last), "the trail starts at the page itself, the last crumb"
        end
      end

      it "works on a process group's page" do
        decision = decide(param: "1", trails: [], place: inside(group), crumbs: [listing, group_page])

        expect(decision.on).to be(true)
        expect(decision.trails).to eq([[group, group_page]])
        expect(decision.start).to eq(1)
      end

      it "does nothing with ?frontdoor=1 outside a space" do
        [place(:outside), place(:kept)].each do |where|
          decision = decide(param: "1", trails: [], place: where)

          expect(decision.on).to be_falsey, "#{where.kind} must keep its navigation"
          expect(decision.trails).to be_empty
        end
      end

      it "does nothing without the parameter and without a visit" do
        [inside(process), place(:kept), place(:outside)].each do |where|
          decision = decide(param: nil, trails: [], place: where, crumbs: front_crumbs)

          expect(decision.on).to be_falsey
          expect(decision.trails).to be_empty
        end
      end

      it "keeps the trail on a page below its start, and grows it" do
        visit = [[process, front]]
        decision = decide(param: nil, trails: visit, place: inside(process), crumbs: idea_crumbs)

        expect(decision.on).to be(true)
        expect(decision.trails).to eq(visit), "nothing new to remember"
        expect(decision.start).to eq(2), "the trail still starts at the front page: … › space › list › idea"
      end

      it "starts the trail at an idea the visitor landed on" do
        decision = decide(param: "1", trails: [], place: inside(process), crumbs: idea_crumbs)

        expect(decision.start).to eq(4), "… › idea, and … is the crumb above it, the list"
        expect(decision.trails).to eq([[process, idea]])
      end

      # Pressing "…" opens the page one step up. It is not under the start, so
      # it becomes the new start, with or without ?frontdoor=1 on its address.
      it "makes the page above the start the new start" do
        ["1", nil].each do |param|
          decision = decide(param:, trails: [[process, idea]], place: inside(process), crumbs: list_crumbs)

          expect(decision.on).to be(true)
          expect(decision.trails).to eq([[process, list]])
          expect(decision.start).to eq(3)
        end
      end

      it "makes a page beside the start the new start" do
        crumbs = [listing, group_page, front, list, other_idea]
        decision = decide(param: nil, trails: [[process, idea]], place: inside(process), crumbs:)

        expect(decision.trails).to eq([[process, other_idea]])
        expect(decision.start).to eq(4)
      end

      it "starts the trail again at a page below the start that is opened with ?frontdoor=1" do
        decision = decide(param: "1", trails: [[process, front]], place: inside(process), crumbs: idea_crumbs)

        expect(decision.trails).to eq([[process, idea]])
        expect(decision.start).to eq(4)
      end

      # A related process or assembly, reached by a link: still without
      # navigation, with a trail of its own, and the first space's trail is
      # kept for its own tab.
      it "gives another space its own trail during a visit" do
        visit = [[assembly, "/assemblies/cambridge-civic-assembly"]]
        decision = decide(param: nil, trails: visit, place: inside(process), crumbs: front_crumbs)

        expect(decision.on).to be(true)
        expect(decision.trails).to eq([[process, front], *visit])
        expect(decision.start).to eq(2)
      end

      it "lets two tabs keep their own trails" do
        visit = [[assembly, "/assemblies/cambridge-civic-assembly"], [process, front]]
        decision = decide(param: nil, trails: visit, place: inside(process), crumbs: idea_crumbs)

        expect(decision.on).to be(true)
        expect(decision.trails).to eq(visit)
        expect(decision.start).to eq(2), "the process keeps its own start while another tab is in the assembly"
      end

      it "puts a space reached from its group under the group's trail" do
        visit = [[group, group_page]]
        decision = decide(param: nil, trails: visit, place: inside(process), crumbs: list_crumbs)

        expect(decision.trails).to eq(visit)
        expect(decision.start).to eq(1), "… › group › space › list"
      end

      it "uses the newest of two trails a page sits under" do
        crumbs = list_crumbs

        expect(decide(param: nil, trails: [[group, group_page], [process, front]], place: inside(process), crumbs:).start).to eq(1)
        expect(decide(param: nil, trails: [[process, front], [group, group_page]], place: inside(process), crumbs:).start).to eq(2)
      end

      it "remembers only so many trails" do
        visit = Array.new(described_class::MAX_TRAILS) { |i| ["assemblies/a#{i}", "/assemblies/a#{i}"] }
        decision = decide(param: "1", trails: visit, place: inside(process), crumbs: front_crumbs)

        expect(decision.trails.size).to eq(described_class::MAX_TRAILS)
        expect(decision.trails.first).to eq([process, front])
        expect(decision.trails).not_to include(visit.last), "the oldest is dropped"
      end

      # The log-in family, the verification pages and the terms of service page.
      it "keeps the pages kept outside a space without navigation during a visit, leading back to the start" do
        visit = [[process, idea], [assembly, "/assemblies/cambridge-civic-assembly"]]
        decision = decide(param: nil, trails: visit, place: place(:kept))

        expect(decision.on).to be(true)
        expect(decision.trails).to eq(visit)
        expect(decision.back).to eq(idea), "Back leads to the start of the newest trail"
      end

      # The home page, a list of all spaces, search, a profile, another help page.
      it "ends the visit on any other page outside a space" do
        ["1", nil].each do |param|
          decision = decide(param:, trails: [[process, front]], place: place(:outside))

          expect(decision.on).to be_falsey
          expect(decision.trails).to be_empty, "the visit is forgotten"
        end
      end

      it "ends the visit on any page with ?frontdoor=0" do
        [inside(process), place(:kept), place(:outside)].each do |where|
          decision = decide(param: "0", trails: [[process, front]], place: where, crumbs: front_crumbs)

          expect(decision.on).to be_falsey
          expect(decision.trails).to be_empty
        end
      end
    end

    describe ".apply" do
      it "leaves the crumb above the space and the space on a front page landed on" do
        view = page(space: process_space, params: { frontdoor: "1" }, path: "/en/processes/dorchester-dollars", crumbs: front_page_list)

        described_class.apply(view)

        expect(labels(view)).to eq(["Participatory Budgeting", "Dorchester Dollars"])
        expect(view.breadcrumb_items.first[:url]).to eq("/en/processes_groups/45?frontdoor=1"), "… opens the page above the space, without navigation"
        expect(view.content[:body_class]).to eq(" frontdoor frontdoor-start")
        expect(view.content[:focus_mode]).to be_nil, "Decidim's own focus mode is not used: it would leave the breadcrumb bar out"
        written = view.cookies.written.fetch(described_class::COOKIE)
        expect(written[:value]).to eq([[process, "/processes/dorchester-dollars"]]), "remembered without the language"
        expect(written[:expires]).to be_nil, "the cookie must end with the browser session"
        expect(written[:httponly]).to be(true)
        expect(written[:same_site]).to eq(:lax)
      end

      it "reads only its own switch, and only 1 and 0" do
        [{ focus: "1" }, { frontdoor: "yes" }, { frontdoors: "1" }].each do |params|
          view = page(space: process_space, params:, path: "/en/processes/dorchester-dollars", crumbs: nil)

          described_class.apply(view) # crumbs: nil would raise if the breadcrumb were asked for

          expect(view.content).to be_empty, params.inspect
          expect(view.cookies.written).to be_empty
        end
      end

      it "shows the way down from the space on an idea reached from the front page" do
        view = page(space: process_space, cookie: [[process, "/processes/dorchester-dollars"]],
                    path: "/en/processes/dorchester-dollars/f/1/proposals/7", crumbs: idea_list)

        described_class.apply(view)

        expect(labels(view)).to eq(["Participatory Budgeting", "Dorchester Dollars", "Proposals", "Barbershop nights"])
        expect(view.content[:body_class]).to eq(" frontdoor"), "below the start a phone shows Decidim's one link up"
        expect(view.breadcrumb_items[1..2].pluck(:url)).to eq(["/en/processes/dorchester-dollars", "/en/processes/dorchester-dollars/f/1/proposals"]),
                                                           "written crumbs keep their own links"
        expect(view.cookies.written).to be_empty, "nothing new to remember"
      end

      # From 1024 px up the trail starts at the space wherever the visitor
      # landed. The page is the start of the visitor's own trail: under
      # 1024 px the stylesheet shows the crumb before the last as "…", so its
      # link carries ?frontdoor=1 as well.
      it "still shows the space on an idea landed on, and marks the page as the start" do
        view = page(space: process_space, params: { frontdoor: "1" }, path: "/en/processes/dorchester-dollars/f/1/proposals/7", crumbs: idea_list)

        described_class.apply(view)

        expect(labels(view)).to eq(["Participatory Budgeting", "Dorchester Dollars", "Proposals", "Barbershop nights"])
        expect(view.breadcrumb_items.first[:url]).to eq("/en/processes_groups/45?frontdoor=1"), "from 1024 px up, … is one step above the space"
        expect(view.breadcrumb_items[1][:url]).to eq("/en/processes/dorchester-dollars")
        expect(view.breadcrumb_items[2][:url]).to eq("/en/processes/dorchester-dollars/f/1/proposals?frontdoor=1"), "under 1024 px, … is one step above the page"
        expect(view.content[:body_class]).to eq(" frontdoor frontdoor-start")
        expect(view.cookies.written.fetch(described_class::COOKIE)[:value]).to eq([[process, "/processes/dorchester-dollars/f/1/proposals/7"]])
      end

      it "keeps the other parameters of a link it adds the switch to" do
        list = [crumb("Processes", "/en/processes?filter%5Bwith_any_date%5D=active&frontdoor=0"),
                crumb("Dorchester Dollars", "/en/processes/dorchester-dollars", resource: process_space)]
        view = page(space: process_space, params: { frontdoor: "1" }, path: "/en/processes/dorchester-dollars", crumbs: list)

        described_class.apply(view)

        expect(view.breadcrumb_items.first[:url]).to eq("/en/processes?filter%5Bwith_any_date%5D=active&frontdoor=1")
      end

      it "starts at the group on a process group's page" do
        view = page(space: nil, params: { frontdoor: "1", id: "45" }, controller_path: described_class::GROUP_PAGES.keys.first,
                    controller_name: "participatory_process_groups", path: "/en/processes_groups/45",
                    crumbs: [crumb("Processes", "/en/processes"), crumb("Participatory Budgeting", "/en/processes_groups/45")])

        described_class.apply(view)

        expect(labels(view)).to eq(["Processes", "Participatory Budgeting"])
        expect(view.breadcrumb_items.first[:url]).to eq("/en/processes?frontdoor=1")
        expect(view.cookies.written.fetch(described_class::COOKIE)[:value]).to eq([[group, group_page]])
      end

      it "shows a child assembly's parent as the dots" do
        child = FrontdoorsStandIns::FakeSpace.new("assemblies", "child")
        list = [crumb("Assemblies", "/en/assemblies"), crumb("Parent", "/en/assemblies/parent", resource: FrontdoorsStandIns::FakeSpace.new("assemblies", "parent")),
                crumb("Child", "/en/assemblies/child", resource: child), crumb("Meetings", "/en/assemblies/child/f/3/meetings")]
        view = page(space: child, params: { frontdoor: "1" }, path: "/en/assemblies/child/f/3/meetings", crumbs: list)

        described_class.apply(view)

        expect(labels(view)).to eq(%w(Parent Child Meetings))
      end

      # The empty items Decidim's templates skip are dropped, and a last crumb
      # without a link (a page that names itself) stands for the page.
      it "skips empty crumbs and takes a last crumb without a link as the page" do
        list = [crumb("Processes", "/en/processes"), crumb("Dorchester Dollars", "/en/processes/dorchester-dollars", resource: process_space), {},
                { label: "Somewhere", active: false }, {}]
        view = page(space: process_space, params: { frontdoor: "1" }, path: "/en/processes/dorchester-dollars/somewhere", crumbs: list)

        described_class.apply(view)

        expect(labels(view)).to eq(["Processes", "Dorchester Dollars", "Somewhere"])
        expect(view.cookies.written.fetch(described_class::COOKIE)[:value]).to eq([[process, "/processes/dorchester-dollars/somewhere"]])
      end

      it "makes the dots the home page when Decidim's list has nothing above the space" do
        view = page(space: process_space, params: { frontdoor: "1" }, path: "/en/processes/dorchester-dollars",
                    crumbs: [crumb("Dorchester Dollars", "/en/processes/dorchester-dollars", resource: process_space)])

        described_class.apply(view)

        expect(labels(view)).to eq(["Home", "Dorchester Dollars"])
        expect(view.breadcrumb_items.first[:url]).to eq("/en?frontdoor=1")
      end

      it "makes no difference of the language in an address" do
        view = page(space: process_space, cookie: [[process, "/processes/dorchester-dollars"]],
                    path: "/es/processes/dorchester-dollars/f/1/proposals",
                    crumbs: [crumb("Procesos", "/es/processes"), crumb("Dorchester Dollars", "/es/processes/dorchester-dollars", resource: process_space),
                             crumb("Propuestas", "/es/processes/dorchester-dollars/f/1/proposals/")])

        described_class.apply(view)

        expect(labels(view)).to eq(["Procesos", "Dorchester Dollars", "Propuestas"])
        expect(view.content[:body_class]).to eq(" frontdoor"), "the page is below the start remembered in another language"
        expect(view.cookies.written).to be_empty, "the same trail in another language"
      end

      # Decidim's own word, in the visitor's language; the page's own crumbs go.
      it "shows Back on the terms of service page and the log-in page during a visit" do
        terms = page(space: nil, cookie: [[process, "/processes/dorchester-dollars/f/1/proposals/7"]], controller_path: "decidim/pages",
                     controller_name: "pages", params: { id: "terms-of-service" }, path: "/en/pages/terms-of-service",
                     crumbs: [crumb("Help", "/en/pages"), crumb("Terms of service", "/en/pages/terms-of-service")])
        log_in = page(space: nil, cookie: [[process, "/processes/dorchester-dollars"]], controller_path: "decidim/devise/sessions",
                      controller_name: "sessions", path: "/en/users/sign_in", crumbs: [])

        described_class.apply(terms)
        described_class.apply(log_in)

        expect(labels(terms)).to eq([I18n.t("layouts.decidim.header.back")])
        expect(terms.breadcrumb_items.first[:url]).to eq("/en/processes/dorchester-dollars/f/1/proposals/7")
        expect(terms.content[:body_class]).to eq(back)
        expect(terms.cookies.deleted).to be_empty
        expect(labels(log_in)).to eq(["Back"])
        expect(log_in.breadcrumb_items.first[:url]).to eq("/en/processes/dorchester-dollars")
        expect(log_in.content[:body_class]).to eq(back)
      end

      it "says Back in the visitor's language, and leads back in it" do
        log_in = page(space: nil, cookie: [[process, "/processes/dorchester-dollars"]], controller_path: "decidim/devise/sessions",
                      controller_name: "sessions", path: "/es/users/sign_in", crumbs: [])

        I18n.with_locale(:es) { described_class.apply(log_in) }

        expect(labels(log_in)).to eq([I18n.t("layouts.decidim.header.back", locale: :es)])
        expect(labels(log_in)).not_to eq(["Back"])
        expect(log_in.breadcrumb_items.first[:url]).to eq("/es/processes/dorchester-dollars")
      end

      # The "verify your account" page a new account is sent to, the list of a
      # participant's verifications and the form of a one-form method are
      # drawn by Decidim's verifications controller.
      it "shows Back on Decidim's verification pages during a visit" do
        view = page(space: nil, cookie: [[process, "/processes/dorchester-dollars"]], controller_path: "decidim/verifications/authorizations",
                    controller_name: "authorizations", path: "/en/authorizations/onboarding_pending", crumbs: [crumb("Account", "/en/account")])

        described_class.apply(view)

        expect(labels(view)).to eq(["Back"])
        expect(view.breadcrumb_items.first[:url]).to eq("/en/processes/dorchester-dollars")
        expect(view.content[:body_class]).to eq(back)
        expect(view.cookies.deleted).to be_empty, "the visit goes on"
      end

      # A verification method with pages of its own is an engine in Decidim's
      # registry; the request carries the routes of the engine that led to it.
      it "shows Back on the pages of every verification method in Decidim's registry" do
        methods = Decidim.authorization_engines

        expect(methods.map(&:name)).to include("id_documents", "postal_letter", "csv_census", "sms")
        methods.each do |method|
          view = page(space: nil, cookie: [[process, "/processes/dorchester-dollars"]], controller_path: "some/module/of/its/own",
                      path: "/en/#{method.name}/", routes: method.engine.routes, crumbs: [])

          described_class.apply(view)

          expect(view.content[:body_class]).to eq(back), method.name
          expect(view.cookies.deleted).to be_empty, method.name
        end
      end

      it "ends the visit on a page of an engine that is not a verification method" do
        view = page(space: nil, cookie: [[process, "/processes/dorchester-dollars"]], controller_path: "some/module/of/its/own",
                    path: "/en/somewhere", routes: Decidim::Core::Engine.routes, crumbs: nil)

        described_class.apply(view) # crumbs: nil would raise if the breadcrumb were asked for

        expect(view.content).to be_empty
        expect(view.cookies.deleted).to eq([described_class::COOKIE])
      end

      it "leaves the log-in, verification and terms of service pages alone when no visit is on" do
        pages = { "decidim/pages" => { id: "terms-of-service" }, "decidim/devise/sessions" => {}, "decidim/verifications/authorizations" => {} }
        pages.each do |controller_path, params|
          view = page(space: nil, params: params.merge(frontdoor: "1"), controller_path:, controller_name: controller_path.split("/").last,
                      path: "/en/somewhere", crumbs: nil)

          described_class.apply(view) # crumbs: nil would raise if the breadcrumb were asked for

          expect(view.content).to be_empty, controller_path
          expect(view.cookies.written).to be_empty, controller_path
        end
      end

      # Search, a profile, another help page, the home page, a list of all
      # spaces, the account: full navigation, the visit is over, and nothing
      # of the page is touched.
      it "ends the visit on any other page outside a space, and does not touch it" do
        pages = { "decidim/pages" => { id: "accessibility" }, "decidim/searches" => {}, "decidim/user_activities" => {}, "decidim/homepage" => {},
                  "decidim/participatory_processes/participatory_processes" => {}, "decidim/account" => {},
                  "decidim/verifications/admin/verifications" => {} }
        pages.each do |controller_path, params|
          view = page(space: nil, cookie: [[process, "/processes/dorchester-dollars"]], controller_path:, params:,
                      controller_name: controller_path.split("/").last, path: "/en/somewhere", crumbs: nil)

          described_class.apply(view) # crumbs: nil would raise if the breadcrumb were asked for

          expect(view.content).to be_empty, "#{controller_path} must keep Decidim's full navigation"
          expect(view.cookies.deleted).to eq([described_class::COOKIE]), "#{controller_path} ends the visit"
        end
      end

      # Once Decidim's service worker is installed, it fetches every page the
      # visitor opens, and the browser marks those requests "empty", not
      # "document". They are the visitor's own pages: a visit starts, goes on
      # and ends on them as on any other.
      context "when Decidim's service worker fetched the page" do
        let(:worker) { { "Sec-Fetch-Dest" => "empty", "Sec-Fetch-Mode" => "navigate" } }

        it "starts a visit on a page of a space" do
          view = page(space: process_space, params: { frontdoor: "1" }, path: "/en/processes/dorchester-dollars", crumbs: front_page_list, headers: worker)

          described_class.apply(view)

          expect(view.content[:body_class]).to eq(" frontdoor frontdoor-start")
          expect(view.cookies.written.fetch(described_class::COOKIE)[:value]).to eq([[process, "/processes/dorchester-dollars"]])
        end

        it "carries the visit into another space, and ends it" do
          space = FrontdoorsStandIns::FakeSpace.new("assemblies", "cambridge-civic-assembly")
          other = page(space:, cookie: [[process, "/processes/dorchester-dollars"]], path: "/en/assemblies/cambridge-civic-assembly",
                       crumbs: [crumb("Assemblies", "/en/assemblies"), crumb("Cambridge Civic Assembly", "/en/assemblies/cambridge-civic-assembly", resource: space)],
                       headers: worker)
          search = page(space: nil, cookie: [[process, "/processes/dorchester-dollars"]], controller_path: "decidim/searches", controller_name: "searches",
                        path: "/en/search", crumbs: nil, headers: worker)

          described_class.apply(other)
          described_class.apply(search)

          expect(other.cookies.written.fetch(described_class::COOKIE)[:value].map(&:first)).to eq([assembly, process]), "the new space is remembered"
          expect(search.cookies.deleted).to eq([described_class::COOKIE]), "full navigation ends the visit"
          expect(search.content).to be_empty
        end
      end

      # Decidim's service worker fetches its offline page once, behind the
      # visitor's back, whatever page they are on. Known by its controller,
      # not by the request's headers.
      it "never starts, changes or ends a visit on the offline page, and never takes its navigation" do
        [{ cookie: [[process, "/processes/dorchester-dollars"]] }, { params: { frontdoor: "1" } }, { params: { frontdoor: "0" }, cookie: [[process, "/x"]] },
         { cookie: [[process, "/x"]], headers: { "Sec-Fetch-Dest" => "document", "Sec-Fetch-Mode" => "navigate" } }].each do |given|
          offline = page(space: nil, controller_path: described_class::OFFLINE_PAGE, controller_name: "offline", path: "/offline", crumbs: nil, **given)

          described_class.apply(offline) # crumbs: nil would raise if the breadcrumb were asked for

          expect(offline.content).to be_empty, "#{given.inspect}: keeps its navigation"
          expect(offline.cookies.written).to be_empty, "#{given.inspect}: starts and changes nothing"
          expect(offline.cookies.deleted).to be_empty, "#{given.inspect}: ends nothing"
        end
      end

      # A page the browser loads ahead of a click, and says so, is not a visit to it.
      it "remembers nothing of a prefetch" do
        headers = { "Sec-Purpose" => "prefetch;prerender" }
        space = page(space: process_space, params: { frontdoor: "1" }, path: "/en/processes/dorchester-dollars", crumbs: front_page_list, headers:)
        search = page(space: nil, cookie: [[process, "/processes/dorchester-dollars"]], controller_path: "decidim/searches", controller_name: "searches",
                      path: "/en/search", crumbs: nil, headers:)

        described_class.apply(space)
        described_class.apply(search)

        expect(space.cookies.written).to be_empty, "no visit starts"
        expect(search.cookies.deleted).to be_empty, "the visit goes on"
      end

      it "looks at nothing without the parameter and without its cookie" do
        view = page(space: process_space, path: "/en/processes/dorchester-dollars", crumbs: nil)

        described_class.apply(view) # crumbs: nil would raise if the breadcrumb were asked for

        expect(view.content).to be_empty
        expect(view.cookies.written).to be_empty
        expect(view.cookies.deleted).to be_empty
      end

      # The cookie is signed. One we did not write reads as nothing.
      it "forgets a cookie it did not write" do
        [nil, "made-up", [], [["a", "//elsewhere.example"]], [%w(a b c)], Array.new(described_class::MAX_TRAILS + 1) { %w(a /b) }].each do |value|
          view = page(space: process_space, raw_cookie: "anything", cookie: value, path: "/en/processes/dorchester-dollars", crumbs: front_page_list)

          described_class.apply(view)

          expect(view.content[:body_class]).to be_nil, "#{value.inspect} must not take a page's navigation"
          expect(view.cookies.deleted).to eq([described_class::COOKIE])
        end
      end

      # Budget voting sets Decidim's focus mode in its own page, which is drawn
      # before the layout: no breadcrumb bar there, and the main bar holds its
      # back link. The visit goes on; the page is left alone.
      it "leaves a page in Decidim's own focus mode alone, and the visit goes on" do
        view = page(space: process_space, params: { frontdoor: "1" }, path: "/en/processes/dorchester-dollars/f/2/budgets/3/projects",
                    crumbs: front_page_list, content: { focus_mode: "true" })

        described_class.apply(view)

        expect(view.content).to eq({ focus_mode: "true" })
        expect(view.breadcrumb_items).to eq(front_page_list), "Decidim's list is not touched"
        expect(view.cookies.written).to have_key(described_class::COOKIE), "the visit is still remembered"
      end
    end
  end
end
