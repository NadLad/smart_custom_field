# frozen_string_literal: true

module SmartCustomField
  # Validates a computed custom field formula when the custom field is saved.
  #
  # The formula is evaluated against a fresh instance of the customized class
  # (Issue, Project, ...) with every referenced custom field set to a sample
  # value, so syntax errors, unknown methods and dangling `cfs[...]`
  # references are caught before the field can be used. Errors caused by a nil
  # attribute are ignored: the blank instance cannot represent real data.
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

      return unless check_cycle(record, source)

      object = record.class.customized_class&.new
      return if object.nil?

      values = fields.transform_values { |field| field.cast_value('1') }
      Evaluator.evaluate(source, object, values)
    rescue *RESCUABLE => e
      # A formula is evaluated against a blank instance, where every optional
      # attribute is nil: `estimated_hours * 2` raises NoMethodError on nil
      # even though it is a perfectly valid formula. Only errors raised by the
      # object itself (a typo in a method name, a syntax error) are the
      # formula's fault.
      record.errors.add(:formula, e.message) unless nil_receiver?(e)
    end

    private

    # Rejects a formula that would close a dependency loop between computed
    # fields. Returns false only when the record must not be saved.
    #
    # A cycle the installation already carries is tolerated: a field whose
    # stored formula is part of a loop has to stay editable, otherwise it could
    # never be fixed from the admin form. The loop is logged instead, so the
    # save that would introduce a *new* one is still refused.
    def check_cycle(record, source)
      cycle = FormulaCycle.detect(record, source)
      return true if cycle.nil?

      if FormulaCycle.stored_cycle(record)
        Rails.logger.warn(
          "[smart_custom_field] custom field #{record.id} still participates in " \
          "a pre-existing formula cycle: #{cycle.join(' -> ')}"
        )
        return true
      end

      record.errors.add(:formula, I18n.t('error_formula_cycle', :path => cycle.join(' -> ')))
      false
    end

    def nil_receiver?(error)
      error.is_a?(NoMethodError) && error.message.match?(/\bfor nil\b|\bNilClass\b/)
    end

    # Custom fields of the same type as the one being validated. A formula may
    # only reference fields that the customized object actually carries.
    def fields_by_id(record, ids)
      return {} if ids.empty?

      CustomField.where(:id => ids, :type => record.type).index_by(&:id)
    end
  end
end
