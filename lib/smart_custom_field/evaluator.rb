# frozen_string_literal: true

require 'timeout'

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
    # Custom field formats exposed to formulas as numbers rather than strings.
    NUMERIC_FORMATS = %w[int float].freeze

    # Seconds one evaluation may run before it is abandoned.
    #
    # A formula is arbitrary Ruby executed inside a save, which means inside a
    # request: an accidental loop or a query over a large table holds a worker
    # until the client gives up, and nothing else in the plugin can stop it.
    # Five seconds is far beyond what reading a handful of values costs, and
    # short enough that a broken formula fails the save instead of the process.
    EVALUATION_TIMEOUT = 5

    # Raised when a formula runs past EVALUATION_TIMEOUT.
    #
    # It is a StandardError, so the rescue that already turns a formula error
    # into a validation message covers it without another branch: a timeout
    # blocks the save and names the limit, it never leaves a half-written
    # value behind.
    class EvaluationTimeout < StandardError; end

    module_function

    # Kept behind a method rather than read from the constant directly, so it
    # can be lowered for a test or raised by an installation whose formulas
    # legitimately need longer: `SmartCustomField::Evaluator.evaluation_timeout = 10`
    # in an initializer.
    def evaluation_timeout
      @evaluation_timeout || EVALUATION_TIMEOUT
    end

    def evaluation_timeout=(seconds)
      @evaluation_timeout = seconds
    end

    # Ids of the custom fields referenced by the formula.
    def custom_field_ids(source)
      source.to_s.scan(CFS_PATTERN).flatten.map(&:to_i).uniq
    end

    # Values exposed to formulas as `cfs[<id>]`, cast to the type of their
    # custom field so that `cfs[12] * 2` works on an integer field. An empty
    # numeric field is exposed as 0: `nil + 1` would otherwise make every
    # arithmetic formula fail as soon as one of its inputs is unset.
    def values_for(object)
      object.custom_field_values.each_with_object({}) do |custom_field_value, hash|
        field = custom_field_value.custom_field
        hash[field.id] = cfs_value(field, custom_field_value.value)
      end
    end

    # One stored value as a formula sees it through `cfs`. Public so a
    # computation can put the value it just produced into its own snapshot
    # without re-reading the object: the two representations must never
    # disagree, or a chained formula reads something a reload would not.
    def cfs_value(field, raw)
      value = field.cast_value(raw)
      value = 0 if value.nil? && NUMERIC_FORMATS.include?(field.field_format)
      value
    end

    # Evaluates `source` against `object`. `values_by_id` maps custom field
    # ids to already cast values and is exposed to the formula as `cfs`.
    #
    # The evaluation is bounded: `Timeout` raises EvaluationTimeout on the
    # thread running the formula, which unwinds it wherever it sits. A formula
    # that rescues StandardError itself can swallow that, so this is a guard
    # against the accidental loop, not against a formula written to resist it.
    def evaluate(source, object, values_by_id = {})
      cfs = values_by_id
      Timeout.timeout(evaluation_timeout, EvaluationTimeout,
                      "the formula took more than #{evaluation_timeout} seconds to evaluate") do
        object.instance_exec { eval(source, binding, '(formula)', 1) }
      end
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
