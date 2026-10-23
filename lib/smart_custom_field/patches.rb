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
      # Patches are registered here as they are added.
      true
    end
  end
end
