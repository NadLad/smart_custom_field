# frozen_string_literal: true

module SmartCustomField
  module Patches
    # Computed fields are never editable: their value is recomputed on every
    # save, so a user-submitted value would be silently overwritten. Redmine
    # uses `read_only_attribute_names` both to build the issue form and to
    # filter mass-assignable attributes, so one override covers both.
    module IssuePatch
      def read_only_attribute_names(user = nil)
        super | computed_custom_field_ids
      end

      private

      def computed_custom_field_ids
        custom_field_values.select { |value| value.custom_field.is_computed? }
                           .map { |value| value.custom_field_id.to_s }
      end
    end
  end
end
