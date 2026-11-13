# frozen_string_literal: true

$LOAD_PATH.push File.expand_path("lib", __dir__)

require "decidim/frontdoors/version"

Gem::Specification.new do |s|
  s.version = Decidim::Frontdoors.version
  s.authors = ["Wildest Future"]
  s.license = "AGPL-3.0-or-later"
  s.homepage = "https://github.com/Wildest-Future/decidim-module-frontdoors"
  s.metadata = {
    "bug_tracker_uri" => "https://github.com/Wildest-Future/decidim-module-frontdoors/issues",
    "changelog_uri" => "https://github.com/Wildest-Future/decidim-module-frontdoors/blob/main/CHANGELOG.md",
    "homepage_uri" => "https://github.com/Wildest-Future/decidim-module-frontdoors",
    "rubygems_mfa_required" => "true",
    "source_code_uri" => "https://github.com/Wildest-Future/decidim-module-frontdoors"
  }
  s.required_ruby_version = "~> 3.4.0"

  s.name = "decidim-frontdoors"
  s.summary = "A front door on any page of a Decidim space"
  s.description = "A link that ends in ?frontdoor=1 opens any page of a participatory space without Decidim's navigation: " \
                  "someone arriving from a flyer walks straight in, without crossing the lobby."

  s.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").select do |f|
      (File.expand_path(f) == __FILE__) ||
        f.start_with?(*%w(app/ config/ lib/ LICENSE-AGPLv3.txt Rakefile README.md CHANGELOG.md))
    end
  end

  s.add_dependency "decidim-core", *Decidim::Frontdoors::COMPAT_DECIDIM_VERSION
  s.add_dependency "deface", "~> 1.9"
end
