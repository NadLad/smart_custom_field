# frozen_string_literal: true

Redmine::Plugin.register :smart_custom_field do
  name 'Smart Custom Field'
  author 'Nader'
  description 'Computed custom fields: the value is calculated by a formula ' \
              'evaluated in the context of the customized object.'
  version SmartCustomField::VERSION
  requires_redmine version_or_higher: '7.0.0'
end

# init.rb is evaluated from a `to_prepare` callback (see
# Redmine::PluginLoader.load), so calling this here applies the patches at
# boot and again after every code reload in development. Registering a nested
# `config.to_prepare` would only run on the *next* prepare cycle.
SmartCustomField::Patches.apply!
