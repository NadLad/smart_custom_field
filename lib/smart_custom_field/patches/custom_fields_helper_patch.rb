# frozen_string_literal: true

module SmartCustomField
  module Patches
    # Helpers used by the admin form hook to render the list of custom fields
    # a formula can reference, and to render a computed field as text on every
    # customizable form.
    module CustomFieldsHelperPatch
      # A computed field is rendered as its value, not as an input: it is
      # derived, so an editable control would only invite an edit that the next
      # save throws away.
      #
      # Overriding the tag builder rather than a per-model hook covers every
      # customizable model at once — Issue, Project, User, Version, Group,
      # Document, TimeEntry and Enumeration all build their custom field rows
      # through this helper.
      def custom_field_tag_with_label(name, custom_value, options = {})
        return super unless custom_value.custom_field.is_computed?

        body =
          if (value = show_value(custom_value)).present?
            content_tag('span', value, :class => 'computed-custom-field-value')
          else
            # A field created after the object was last saved has no value yet.
            content_tag('span', l(:label_computed_value_pending),
                        :class => 'computed-custom-field-value info')
          end
        # No `for` attribute: there is no control to focus.
        custom_field_label_tag(name, custom_value, options.merge(:for_tag_id => nil)) + body
      end

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

      # Options of the expression builder's field list. The format travels with
      # each option so the builder can pick the right operators and quote the
      # value the way the field expects it.
      def formula_builder_field_options(custom_field)
        options = custom_fields_for_formula(custom_field).map do |field|
          content_tag(:option,
                      "#{field.name} (cfs[#{field.id}])",
                      :value => field.id,
                      :data => {:format => field.field_format})
        end
        safe_join(options)
      end
    end
  end
end
