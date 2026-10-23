# frozen_string_literal: true

# Redmine evaluates this file inside `Rails.application.routes.draw` (see
# config/routes.rb in the core), so the routes are declared at the top level
# rather than wrapped in their own draw block.
post 'smart_custom_field/preview', :to => 'smart_custom_field/previews#preview'
get 'smart_custom_field/explain', :to => 'smart_custom_field/previews#explain'
