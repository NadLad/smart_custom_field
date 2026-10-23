# frozen_string_literal: true

module SmartCustomField
  # Validates a computed custom field formula when the custom field is saved.
  #
  # The formula is evaluated against a fresh instance of the customized class
  # (Issue, Project, ...) with every referenced custom field set to a sample
  # value, so syntax errors, unknown methods and dangling `cfs[...]`
  # references are caught before the field can be used.
  class FormulaValidator < ActiveModel::Validator
    # SyntaxError is a ScriptError, not a StandardError: both have to be
    # rescued to turn a broken formula into a validation message.
    RESCUABLE = [StandardError, ScriptError].freeze

    def validate(record)
      return unless record.is_computed?

      source = record.formula.to_s
      if source.strip.empty?
        record.errors.add(:formula, :blank)
        return
      end

      ids = Evaluator.custom_field_ids(source)
      fields = fields_by_id(record, ids)
      unknown = ids - fields.keys
      if unknown.any?
        record.errors.add(:formula, I18n.t('error_unknown_custom_field_in_formula',
                                           :ids => unknown.join(', ')))
        return
      end

      object = record.class.customized_class&.new
      return if object.nil?

      values = fields.transform_values { |field| field.cast_value('1') }
      Evaluator.evaluate(source, object, values)
    rescue *RESCUABLE => e
      record.errors.add(:formula, e.message)
    end

    private

    # Custom fields of the same type as the one being validated. A formula may
    # only reference fields that the customized object actually carries.
    def fields_by_id(record, ids)
      return {} if ids.empty?

      CustomField.where(:id => ids, :type => record.type).index_by(&:id)
    end
  end
end
