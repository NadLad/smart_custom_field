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
      true
    end

    def self.include_patch(target, patch)
      target.include(patch) unless target.include?(patch)
    end

    def self.prepend_patch(target, patch)
      target.prepend(patch) unless target.ancestors.include?(patch)
    end

    private_class_method :include_patch, :prepend_patch
  end
end
