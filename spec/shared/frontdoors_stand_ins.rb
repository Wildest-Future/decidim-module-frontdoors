# frozen_string_literal: true

# Stand-ins for a page, so that the rule and what it does to a page can be
# checked without drawing one.
module FrontdoorsStandIns
  PROCESS = "participatory_processes/dorchester-dollars"
  ASSEMBLY = "assemblies/cambridge-civic-assembly"
  GROUP = "participatory_process_groups/45"

  # Addresses as the rule sees them: no language, top crumb first.
  LISTING = "/processes"
  GROUP_PAGE = "/processes_groups/45"
  FRONT = "/processes/dorchester-dollars"
  LIST = "/processes/dorchester-dollars/f/1/proposals"
  IDEA = "/processes/dorchester-dollars/f/1/proposals/7"
  OTHER_IDEA = "/processes/dorchester-dollars/f/1/proposals/8"
  FRONT_CRUMBS = [LISTING, GROUP_PAGE, FRONT].freeze
  LIST_CRUMBS = [LISTING, GROUP_PAGE, FRONT, LIST].freeze
  IDEA_CRUMBS = [LISTING, GROUP_PAGE, FRONT, LIST, IDEA].freeze

  FakeSpace = Struct.new(:kind, :slug) do
    def manifest
      Struct.new(:name).new(kind.to_sym)
    end
  end
  PROCESS_SPACE = FakeSpace.new("participatory_processes", "dorchester-dollars")

  # The browser's cookies as the module uses them: the raw value (is there
  # one?), the signed reading, and what was written or deleted.
  class FakeCookies
    attr_reader :written, :deleted

    def initialize(raw, value)
      @raw = raw
      @value = value
      @written = {}
      @deleted = []
    end

    def [](_name)
      @raw
    end

    def []=(name, options)
      @written[name] = options
    end

    def signed
      Signed.new(self, @value)
    end

    def delete(name)
      @deleted << name
    end

    Signed = Struct.new(:jar, :value) do
      def [](_name)
        value
      end

      def []=(name, options)
        jar[name] = options
      end
    end
  end

  # What Decidim::Frontdoors.apply asks of a view, and nothing else.
  class FakeView
    attr_reader :cookies

    def initialize(space:, crumbs:, cookie: nil, raw_cookie: nil, **given)
      @space = space
      @crumbs = crumbs
      @cookies = FakeCookies.new(raw_cookie || (cookie && "signed"), cookie)
      @given = { params: {}, content: {}, controller_name: "x", controller_path: "decidim/x", path: "/en/x" }.merge(given)
      @given[:params] = @given[:params].with_indifferent_access
    end

    [:params, :content, :controller_name, :controller_path].each do |name|
      define_method(name) { @given.fetch(name) }
    end

    # Decidim's helper: the same array on every call.
    def breadcrumb_items
      @crumbs || raise("the breadcrumb was asked for")
    end

    # Pages outside a space have no such helper at all.
    def respond_to_missing?(name, include_private = false)
      (name == :current_participatory_space && !@space.nil?) || super
    end

    def method_missing(name, *)
      name == :current_participatory_space && @space ? @space : super
    end

    def request
      Struct.new(:path, :ssl?, :headers, :routes).new(@given.fetch(:path), false, @given.fetch(:headers, {}), @given[:routes])
    end

    def decidim
      Struct.new(:root_path).new("/en")
    end

    def content_for?(name)
      content.has_key?(name)
    end

    def content_for(name, value)
      content[name] = "#{content[name]}#{value}"
    end
  end

  def decide(**)
    Decidim::Frontdoors.decide(**)
  end

  def inside(key)
    place(:inside, key)
  end

  def place(kind, key = nil)
    Decidim::Frontdoors::Place.new(kind:, key:)
  end

  def crumb(label, url, resource: nil)
    { label:, url:, active: false, resource: }.compact
  end

  def labels(view)
    view.breadcrumb_items.pluck(:label)
  end

  # Decidim's list on a process's front page and on one of its ideas.
  def front_page_list
    [crumb("Processes", "/en/processes"), crumb("Participatory Budgeting", "/en/processes_groups/45"),
     crumb("Dorchester Dollars", "/en/processes/dorchester-dollars", resource: PROCESS_SPACE)]
  end

  def idea_list
    [*front_page_list, crumb("Proposals", "/en/processes/dorchester-dollars/f/1/proposals"), {},
     crumb("Barbershop nights", "/en/processes/dorchester-dollars/f/1/proposals/7")]
  end

  def page(**)
    FakeView.new(**)
  end

  # A file of an installed Decidim gem, as it was released.
  def decidim_file(gem_name, path)
    File.read(File.join(Gem.loaded_specs.fetch(gem_name).full_gem_path, path))
  end
end
