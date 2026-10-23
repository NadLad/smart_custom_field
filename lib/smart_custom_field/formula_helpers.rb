# frozen_string_literal: true

module SmartCustomField
  # Cross-object access for formulas.
  #
  # `cfs` only sees the custom fields of the object being computed. A formula
  # that needs a value carried by the project, the parent issue or the
  # assignee would otherwise have to walk `object.custom_field_values` by hand
  # and cast the result itself:
  #
  #   cf(project, 12) * 2
  #   parent&.cfs[5].to_i + 1
  #
  # Both go through the same cast as `cfs`, so the same field is never a string
  # in one formula and an integer in another.
  module FormulaHelpers
    CACHE_KEY = :smart_custom_field_formula_cache

    module_function

    # Values of `object`, cast exactly like `cfs` of the computed object.
    #
    # Cached for the duration of one computation: a formula reading three
    # fields of the same project loads that project's custom values once
    # instead of three times.
    def cfs_for(object)
      return {} if object.nil?

      # An unsaved object has no id to key the cache on, and two fresh
      # instances of the same class would share an entry.
      return Evaluator.values_for(object) if object.id.nil?

      cache[key_for(object)] ||= Evaluator.values_for(object)
    end

    def cf(object, custom_field_id)
      cfs_for(object)[custom_field_id.to_i]
    end

    # Runs the block with an empty cache and restores the previous one
    # afterwards, so a nested computation can never serve stale values to the
    # computation that triggered it.
    def with_cache
      previous = Thread.current[CACHE_KEY]
      Thread.current[CACHE_KEY] = {}
      yield
    ensure
      Thread.current[CACHE_KEY] = previous
    end

    def cache
      # Outside `with_cache` the values are computed on demand and thrown away:
      # a thread that evaluated one formula must not keep its objects alive.
      Thread.current[CACHE_KEY] || {}
    end

    def key_for(object)
      [object.class.name, object.id]
    end

    private_class_method :cache, :key_for
  end
end
