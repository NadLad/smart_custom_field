# frozen_string_literal: true

module SmartCustomField
  # Marks the window during which the plugin writes computed values itself.
  #
  # A computed value is derived: a client must never choose it, so
  # `CustomizablePatch#custom_field_values=` drops the ids of computed fields
  # from anything assigned from the outside. The computation itself still has
  # to write them, so it opens this window around its own assignment.
  #
  # The flag is thread-local and counted, so a nested computation (a formula
  # that saves another object) cannot close the window its caller opened.
  module FormulaComputation
    KEY = :smart_custom_field_computing

    module_function

    def writing?
      Thread.current[KEY].to_i.positive?
    end

    def writing
      Thread.current[KEY] = Thread.current[KEY].to_i + 1
      yield
    ensure
      Thread.current[KEY] = Thread.current[KEY].to_i - 1
    end
  end
end
