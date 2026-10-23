# frozen_string_literal: true

module SmartCustomField
  # Evaluates a computed custom field formula.
  #
  # A formula is Ruby code evaluated with `self` bound to the customized
  # object (issue, project, user...), so model attributes and methods are
  # available. `cfs` is a hash of custom field values indexed by custom field
  # id:
  #
  #   cfs[12] * 2 + cfs[13]
  #   (self.estimated_hours || 0) * 2
  #
  # Keeping evaluation in one place makes it possible to replace `eval` with a
  # restricted interpreter later without touching the patches.
  module Evaluator
    module_function

    # Ids of the custom fields referenced by the formula.
    def custom_field_ids(source)
      source.to_s.scan(CFS_PATTERN).flatten.map(&:to_i).uniq
    end

    # Evaluates `source` against `object`. `values_by_id` maps custom field
    # ids to already cast values and is exposed to the formula as `cfs`.
    def evaluate(source, object, values_by_id = {})
      cfs = values_by_id
      object.instance_exec { eval(source, binding, '(formula)', 1) }
    end

    # Converts a raw formula result into the string Redmine stores in
    # custom_values, following the format of the target custom field.
    def cast(custom_field, value)
      return value.map { |v| cast(custom_field, v) } if value.is_a?(Array)

      result =
        case custom_field.field_format
        when 'bool'
          value.is_a?(TrueClass) ? '1' : '0'
        when 'int'
          value.to_i
        else
          value.respond_to?(:id) ? value.id : value
        end
      result.to_s
    end
  end
end
