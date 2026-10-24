# frozen_string_literal: true

module SmartCustomField
  module Patches
    # Adds the computed field behaviour to CustomField: the two extra
    # attributes are assignable from the admin form, and a computed field
    # validates its formula.
    module CustomFieldPatch
      extend ActiveSupport::Concern

      included do
        safe_attributes 'formula', 'is_computed'

        before_validation :normalize_formula
        validates_with SmartCustomField::FormulaValidator, :if => :is_computed?
        after_update :log_formula_change
      end

      # A field cannot switch between computed and editable once created:
      # existing values would silently stop being (or start being) computed.
      def is_computed=(value)
        super if new_record?
      end

      # Number of objects that already carry a value produced by the formula
      # currently stored. Editing the formula does not rewrite them: they keep
      # the old result until their object is saved again or the backfill runs.
      #
      # Counted on distinct objects rather than on rows: a multi-valued field
      # stores one row per value.
      def stored_value_count
        return 0 if new_record? || id.nil?

        CustomValue.where(:custom_field_id => id)
                   .where.not(:value => [nil, ''])
                   .distinct
                   .count(:customized_id)
      end

      private

      # The admin form warns before the save; this leaves a trace for a formula
      # changed from the console or by an import, where nobody sees the form.
      def log_formula_change
        return unless saved_change_to_formula? && is_computed?

        count = stored_value_count
        return unless count.positive?

        Rails.logger.info(
          "[smart_custom_field] formula of custom field #{id} changed: " \
          "#{count} stored value(s) keep the result of the previous formula " \
          'until they are recomputed (rake smart_custom_field:recompute_all)'
        )
      end

      def normalize_formula
        self.formula = formula.strip if formula.present?
      end
    end
  end
end
