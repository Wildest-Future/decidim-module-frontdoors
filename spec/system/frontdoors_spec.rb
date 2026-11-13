# frozen_string_literal: true

require "spec_helper"

# Real pages of the test application, drawn in a browser at laptop width.
# The walk (script/walk) goes further: both widths, every kind of space,
# Decidim's service worker, signing up.
describe "Frontdoors" do
  let(:organization) { create(:organization, available_authorizations: %w(dummy_authorization_handler id_documents)) }
  let!(:participatory_process) { create(:participatory_process, :with_steps, organization:) }
  let!(:component) { create(:proposal_component, participatory_space: participatory_process) }
  let!(:proposal) { create(:proposal, component:) }
  let(:space_title) { translated(participatory_process.title) }
  let(:space_path) { "/processes/#{participatory_process.slug}" }
  let(:list_path) { "#{space_path}/f/#{component.id}/proposals" }
  let(:band) { "header .menu-bar__container" }
  let(:trail) { "header .menu-bar__breadcrumb-desktop" }

  before do
    switch_to_host(organization.host)
  end

  def our_cookie
    page.driver.browser.manage.all_cookies.find { |cookie| cookie[:name] == Decidim::Frontdoors::COOKIE }
  end

  def height_of(selector)
    page.evaluate_script("document.querySelector(#{selector.to_json}).getBoundingClientRect().height")
  end

  # The links of the trail that are shown, as the browser draws them: what
  # each shows ("…" is drawn by the stylesheet in place of a crumb's name,
  # which stays in the page for screen readers) and how tall it is.
  def links_of_the_trail
    page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll("#{trail} > a")).filter((link) => link.getClientRects().length > 0).map((link) => ({
        shows: getComputedStyle(link, "::after").content.includes("…") ? "…" : link.innerText.trim(),
        name: link.textContent.trim(),
        height: link.getBoundingClientRect().height
      }))
    JS
  end

  def expect_decidims_own_page
    expect(page).to have_css("#main-bar")
    expect(page).to have_no_css("body.frontdoor")
    expect(page).to have_no_css("body[class*='frontdoor']")
  end

  def expect_a_page_without_navigation
    expect(page).to have_css("body.frontdoor")
    expect(page).to have_no_css("#main-bar")
    expect(page).to have_css(band)
    expect(height_of(band)).to eq(48)
  end

  it "does nothing without the parameter and without the cookie" do
    visit space_path

    expect(page).to have_content(space_title)
    expect_decidims_own_page
    expect(our_cookie).to be_nil

    visit list_path

    expect_decidims_own_page
    expect(our_cookie).to be_nil
  end

  it "opens a page of a space without navigation with ?frontdoor=1" do
    visit "#{space_path}?frontdoor=1"

    expect_a_page_without_navigation
    expect(page).to have_css("body.frontdoor.frontdoor-start")
    within trail do
      expect(page).to have_content(space_title)
      expect(page).to have_no_content("Home")
    end
    expect(links_of_the_trail).to eq([{ "shows" => "…", "name" => "Processes", "height" => 44 }])
    expect(page).to have_content(space_title)
    expect(page).to have_no_css(".menu-bar__actions", visible: :visible)
    within "footer" do
      expect(page).to have_link(I18n.t("layouts.decidim.footer.terms_of_service"), href: %r{/pages/terms-of-service\z})
      expect(page).to have_link(I18n.t("layouts.decidim.footer.data_consent_settings"))
      expect(page).to have_no_css(".main-footer__top")
      expect(page).to have_css("a", count: 2)
    end
    expect(our_cookie).to include(http_only: true, same_site: "Lax")
    expect(our_cookie[:expires]).to be_nil, "the cookie ends with the browser session"
  end

  it "stays that way on the next page, by the cookie alone, and the trail grows" do
    visit "#{space_path}?frontdoor=1"
    visit list_path

    expect_a_page_without_navigation
    expect(page).to have_no_css("body.frontdoor-start")
    within trail do
      expect(page).to have_link(space_title, href: /#{space_path}\z/)
      expect(page).to have_content("Proposals")
    end
    expect(links_of_the_trail.pluck("shows")).to eq(["…", space_title])
    expect(links_of_the_trail.pluck("height")).to eq([44, 44])
  end

  it "ends the visit on the home page, and it stays ended" do
    visit "#{space_path}?frontdoor=1"
    expect_a_page_without_navigation

    visit "/"

    expect_decidims_own_page
    expect(our_cookie).to be_nil

    visit space_path

    expect(page).to have_content(space_title)
    expect_decidims_own_page
  end

  it "ends the visit with ?frontdoor=0" do
    visit "#{space_path}?frontdoor=1"
    expect_a_page_without_navigation

    visit "#{list_path}?frontdoor=0"

    expect_decidims_own_page
    expect(our_cookie).to be_nil

    visit space_path

    expect_decidims_own_page
  end

  it "shows Back on the log-in page during a visit, and leads back" do
    visit "#{list_path}?frontdoor=1"
    visit "/users/sign_in"

    expect_a_page_without_navigation
    expect(page).to have_css("body.frontdoor.frontdoor-back")
    expect(page).to have_css("#{trail} a", count: 1, visible: :visible)
    within(trail) { click_on "Back" }

    expect(page).to have_current_path(/#{list_path}\z/)
    expect_a_page_without_navigation
  end

  it "leaves the log-in page alone when no visit is on" do
    visit "/users/sign_in?frontdoor=1"

    expect_decidims_own_page
    expect(our_cookie).to be_nil
  end

  it "says Back in the visitor's language" do
    visit "/es#{space_path}?frontdoor=1"
    visit "/es/users/sign_in"

    expect_a_page_without_navigation
    within(trail) { expect(page).to have_link("Atrás", href: %r{/es#{space_path}\z}) }
  end

  context "when a participant is logged in" do
    let(:user) { create(:user, :confirmed, organization:) }

    before do
      login_as user, scope: :user
    end

    # The list of a participant's verifications and the form of a method that
    # is one form are drawn by Decidim's verifications controller; a method
    # with pages of its own (here: identity documents) by its own engine,
    # which Decidim's registry names.
    it "shows Back on Decidim's verification pages during a visit" do
      visit "#{space_path}?frontdoor=1"

      ["/en/authorizations", "/en/authorizations/new?handler=dummy_authorization_handler", "/en/id_documents/"].each do |address|
        visit address

        expect(page).to have_css("body.frontdoor.frontdoor-back"), address
        within(trail) { expect(page).to have_link("Back", href: /#{space_path}\z/) }
        expect(our_cookie).to be_present
      end
    end

    it "ends the visit on the account page" do
      visit "#{space_path}?frontdoor=1"
      visit "/account"

      expect_decidims_own_page
      expect(our_cookie).to be_nil
    end

    it "leaves the verification pages alone when no visit is on" do
      visit "/en/authorizations?frontdoor=1"

      expect_decidims_own_page
      expect(our_cookie).to be_nil
    end
  end
end
