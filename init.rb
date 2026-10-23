# frozen_string_literal: true

Redmine::Plugin.register :smart_custom_field do
  name 'Smart Custom Field'
  author 'Nader'
  description 'Computed custom fields: the value is calculated by a formula ' \
              'evaluated in the context of the customized object.'
  version SmartCustomField::VERSION
  requires_redmine version_or_higher: '7.0.0'
end

# Re-applied on every code reload so the patches survive Zeitwerk reloading
# in development, and applied once at boot in production.
Rails.application.config.to_prepare do
  SmartCustomField::Patches.apply!
end
