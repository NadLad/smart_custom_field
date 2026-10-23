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

        before_validation :normalize_formula, :if => :is_computed?
        validates_with SmartCustomField::FormulaValidator, :if => :is_computed?
      end

      # A field cannot switch between computed and editable once created:
      # existing values would silently stop being (or start being) computed.
      def is_computed=(value)
        super if new_record?
      end

      private

      def normalize_formula
        self.formula = formula.to_s.strip
      end
    end
  end
end
