# frozen_string_literal: true

module SmartCustomField
  # Adds the computed field controls to the custom field admin form.
  #
  # Redmine eager loads every plugin's `lib` directory, so subclassing
  # ViewListener is enough to register the hook: `Redmine::Hook.add_listener`
  # is called by the `inherited` callback of Redmine::Hook::Listener.
  class HookListener < Redmine::Hook::ViewListener
    render_on :view_custom_fields_form_upper_box,
              :partial => 'hooks/smart_custom_field/view_custom_fields_form_upper_box'
  end
end
