# frozen_string_literal: true

module SmartCustomField
  # Builds the payload shown by the admin preview panel and by the explain
  # endpoint.
  #
  # Read only: the formula is evaluated against a real object, nothing is
  # written. The same builder serves both surfaces so a formula cannot show one
  # result while saving another.
  module Preview
    module_function

    # Models a formula may be tested against. `object_type` comes from the
    # request, so the list is closed: the endpoint cannot be used to
    # instantiate an arbitrary constant.
    def allowed_types
      Patches::CUSTOMIZABLE_MODELS
    end

    def for(source, object, field = nil)
      analysis = StaticAnalyzer.analyze(source, object.class)
      payload = {
        'ok' => true,
        'formula' => source,
        'object' => { 'type' => object.class.name, 'id' => object.id },
        'inputs' => inputs(object, analysis.referenced_ids),
        'warnings' => analysis.warnings
      }

      begin
        raw = Evaluator.evaluate(source, object, Evaluator.values_for(object))
        payload['result'] = raw.to_s
        payload['result_class'] = raw.class.name
        payload['cast_value'] = field ? Evaluator.cast(field, raw) : raw.to_s
      rescue *FormulaValidator::RESCUABLE => e
        payload['ok'] = false
        payload['error'] = e.message
      end

      payload
    end

    # The custom values the formula actually reads, with their cast value: that
    # is the difference between "it returns 42" and "why 42".
    def inputs(object, referenced_ids)
      return [] if referenced_ids.empty?

      values = Evaluator.values_for(object)
      object.custom_field_values.filter_map do |custom_field_value|
        field = custom_field_value.custom_field
        next unless referenced_ids.include?(field.id)

        {
          'id' => field.id,
          'name' => field.name,
          'format' => field.field_format,
          'raw' => custom_field_value.value.to_s,
          'cast' => values[field.id].to_s
        }
      end
    end
  end
end
