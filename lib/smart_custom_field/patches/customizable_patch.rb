# frozen_string_literal: true

module SmartCustomField
  module Patches
    # Recomputes the value of every computed custom field before the object is
    # validated, so the fresh value goes through Redmine's own custom value
    # validation and gets persisted by `save_custom_field_values`.
    module CustomizablePatch
      extend ActiveSupport::Concern

      included do
        before_validation :compute_computed_custom_fields
      end

      private

      def compute_computed_custom_fields
        computed = custom_field_values.select { |value| value.custom_field.is_computed? }
        return if computed.empty?

        new_values = {}
        computed.each do |custom_field_value|
          field = custom_field_value.custom_field
          begin
            result = Evaluator.evaluate(field.formula, self, formula_values)
            new_values[field.id] = Evaluator.cast(field, result)
          rescue *FormulaValidator::RESCUABLE => e
            errors.add(:base, I18n.t(:error_while_formula_computing,
                                     :custom_field_name => field.name,
                                     :message => e.message))
          end
        end

        # `custom_field_values=` flags the values as changed, which makes
        # Redmine re-validate and re-save them.
        self.custom_field_values = new_values if new_values.any?
      end

      # Values exposed to formulas as `cfs[<id>]`, cast to the type of their
      # custom field so that `cfs[12] * 2` works on an integer field.
      def formula_values
        Evaluator.values_for(self)
      end
    end
  end
end
