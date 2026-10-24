# frozen_string_literal: true

module SmartCustomField
  # Entry point for every monkey patch.
  #
  # Called from init.rb, which Rails itself evaluates from a `to_prepare`
  # callback, so this runs at boot and again after each code reload in
  # development. Every patch registered here must therefore be idempotent:
  # check `ancestors` before including or prepending a module.
  module Patches
    # Every model declaring `acts_as_customizable` in Redmine 7.0.
    CUSTOMIZABLE_MODELS = %w[
      Document Enumeration Group Issue Project TimeEntry User Version
    ].freeze

    def self.apply!
      include_patch(CustomField, CustomFieldPatch)
      CUSTOMIZABLE_MODELS.each { |name| include_patch(name.constantize, CustomizablePatch) }
      prepend_patch(Issue, IssuePatch)
      # Prepended, not included: this patch overrides an existing helper, and an
      # included module sits *below* the class that defines it in the ancestor
      # chain, so the override would never be reached.
      prepend_patch(CustomFieldsHelper, CustomFieldsHelperPatch)
      register_hook_listener!
      true
    end

    # Plugin `lib` directories are only eager loaded when Rails eager loads, so
    # the listener class is referenced here to make sure it is defined in every
    # environment. Redmine keeps the registered listeners in a class variable
    # and has no API to unregister one: after a code reload the constant is
    # redefined, so the previous class is dropped to avoid rendering the admin
    # form twice.
    def self.register_hook_listener!
      classes = Redmine::Hook.class_variable_get(:@@listener_classes)
      classes.reject! do |klass|
        klass.name == HookListener.name && !klass.equal?(HookListener)
      end
      Redmine::Hook.add_listener(HookListener) unless classes.include?(HookListener)
      Redmine::Hook.clear_listeners_instances
    end

    def self.include_patch(target, patch)
      target.include(patch) unless target.include?(patch)
    end

    def self.prepend_patch(target, patch)
      target.prepend(patch) unless target.ancestors.include?(patch)
    end

    private_class_method :include_patch, :prepend_patch, :register_hook_listener!
  end
end
