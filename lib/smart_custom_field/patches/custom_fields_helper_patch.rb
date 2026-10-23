# frozen_string_literal: true

module SmartCustomField
  module Patches
    # Helpers used by the admin form hook to render the list of custom fields
    # a formula can reference.
    module CustomFieldsHelperPatch
      # Select tag listing the custom fields of the same type as `custom_field`,
      # valued by their id: a double click in the form inserts `cfs[<id>]`.
      def render_computed_custom_fields_select(custom_field)
        fields = custom_fields_for_formula(custom_field)
        if fields.empty?
          return content_tag(:em, l(:label_no_available_custom_fields), :class => 'info')
        end

        options = fields.map { |field| ["#{field.name} (cfs[#{field.id}])", field.id] }
        select_tag(
          'smart_custom_field_available',
          options_for_select(options),
          :id => 'smart-custom-field-available',
          :size => [fields.size, 8].min,
          :class => 'computed-custom-field-select'
        )
      end

      # Custom fields a formula of `custom_field` may reference: every field of
      # the same type except itself. Computed fields are included on purpose,
      # chaining a computed field into another one is allowed.
      def custom_fields_for_formula(custom_field)
        scope = custom_field.class.sorted
        scope = scope.where.not(:id => custom_field.id) unless custom_field.new_record?
        scope.to_a
      end
    end
  end
end
