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

      # Values exposed to formulas as `cfs[<id>]`, cast to the type of their
      # custom field so that `cfs[12] * 2` works on an integer field.
      #
      # Public, and therefore reachable from another object: `parent&.cfs[5]`
      # or `assigned_to.cfs[3]`.
      def cfs
        FormulaHelpers.cfs_for(self)
      end

      # Value of one custom field of any customizable object, cast like `cfs`:
      # `cf(project, 12)`. Defined on the models rather than on the evaluator so
      # a formula can call it without a receiver.
      def cf(object, custom_field_id)
        FormulaHelpers.cf(object, custom_field_id)
      end

      private

      def compute_computed_custom_fields
        computed = custom_field_values.select { |value| value.custom_field.is_computed? }
        return if computed.empty?

        # One cache per save: the values of a related object are read once,
        # and the next save starts from a clean slate.
        FormulaHelpers.with_cache { compute_into(computed) }
      end

      def compute_into(computed)
        new_values = {}
        computed.each do |custom_field_value|
          field = custom_field_value.custom_field
          begin
            result = Evaluator.evaluate(field.formula, self, cfs)
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
    end
  end
end
