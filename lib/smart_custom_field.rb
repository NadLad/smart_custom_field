# frozen_string_literal: true

module SmartCustomField
  VERSION = '0.3.0'
  PLUGIN_ID = :smart_custom_field

  # Placeholder syntax used inside formulas: cfs[42] refers to custom field 42.
  CFS_PATTERN = /cfs\[(\d+)\]/
end
