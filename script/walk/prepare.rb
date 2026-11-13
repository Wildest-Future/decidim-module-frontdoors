# frozen_string_literal: true

# Makes the development application's seed data fit for the walk
# (script/walk/walk.cjs). Decidim's seeds are random and leave out two
# things the walk needs; this sets them, and can be run again at any time:
#
#   docker compose run --rm -w /app/development_app app bin/rails runner /app/script/walk/prepare.rb
#
# 1. Voting is open in the budget of the first process that sits in a process
#    group (the seeds pick "enabled", "disabled" or "finished" at random).
# 2. Liking a proposal in that process requires two verifications, the two
#    example methods of a development application, so that a new account is
#    sent to Decidim's "verify your account" page. Sign-up is switched on.
#
# It changes records of the development application only. Nothing here is
# part of the module.

organization = Decidim::Organization.order(:id).first
process = Decidim::ParticipatoryProcess.where(organization:).where.not(decidim_participatory_process_group_id: nil).where.not(published_at: nil).order(:id).first
abort "No published process in a process group: run `rake development_app` again." unless process

budgets = process.components.find_by(manifest_name: "budgets")
# Written as stored: the component's own writers take one part of it at a time.
stored = budgets.attributes["settings"].deep_dup
stored["steps"] = (stored["steps"] || {}).transform_values { |step| step.merge("votes" => "enabled") }
stored["default_step"] = stored["default_step"].merge("votes" => "enabled") if stored["default_step"]
budgets[:settings] = stored
budgets.save!

methods = %w(dummy_authorization_handler another_dummy_authorization_handler)
missing = methods - Decidim.authorization_workflows.map(&:name)
abort "This application has no #{missing.join(", ")}: the walk wants an application made by `rake development_app`." if missing.any?
organization.update!(available_authorizations: (organization.available_authorizations + methods).uniq, users_registration_mode: :enabled)
proposals = process.components.find_by(manifest_name: "proposals")
proposals.update!(permissions: { "like" => { "authorization_handlers" => methods.index_with { {} } } })

puts "Ready for the walk: #{organization.host}"
puts "  process /processes/#{process.slug}: voting open in its budget (#{budgets.reload.current_settings.votes}); " \
     "liking a proposal requires #{proposals.reload.permissions.dig("like", "authorization_handlers").keys.join(" and ")}"
