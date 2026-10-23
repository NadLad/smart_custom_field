# frozen_string_literal: true

module SmartCustomField
  # Entry point for every monkey patch.
  #
  # Called from init.rb inside `Rails.application.config.to_prepare`, so it
  # runs again after each code reload in development. Every patch registered
  # here must therefore be idempotent: check `ancestors` before including or
  # prepending a module.
  module Patches
    def self.apply!
      include_patch(CustomField, CustomFieldPatch)
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
