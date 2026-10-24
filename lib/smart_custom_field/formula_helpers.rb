# frozen_string_literal: true

module SmartCustomField
  # Cross-object access and aggregations for formulas.
  #
  # `cfs` only sees the custom fields of the object being computed. A formula
  # that needs a value carried by the project, the parent issue or the
  # assignee would otherwise have to walk `object.custom_field_values` by hand
  # and cast the result itself:
  #
  #   cf(project, 12) * 2
  #   parent&.cfs[5].to_i + 1
  #   cf_sum(children, 7)
  #   cf_avg(subtree, 7)
  #
  # Everything here goes through the same cast as `cfs`, so the same field is
  # never a string in one formula and an integer in another.
  module FormulaHelpers
    CACHE_KEY = :smart_custom_field_formula_cache

    # A formula runs inside a save: an unbounded collection would turn it into
    # a full table scan, and an unbounded tree walk into an outage.
    MAX_COLLECTION = 1000
    MAX_DEPTH = 5

    # Raised when a formula asks for more than the caps allow. It is a
    # StandardError, so the computation turns it into a validation error
    # instead of leaving the value half written.
    class AggregationError < StandardError; end

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

      cached(:cast, object) { Evaluator.values_for(object) }
    end

    def cf(object, custom_field_id)
      cfs_for(object)[custom_field_id.to_i]
    end

    # --- aggregations -----------------------------------------------------

    # Sum of one custom field over a collection: `cf_sum(children, 7)`.
    # Unset values are skipped, so a total is not inflated by them either.
    def cf_sum(collection, custom_field_id)
      numbers(collection, custom_field_id).sum
    end

    # Average over the values that are actually set. Rounded to two decimals
    # so a float field does not end up storing float noise.
    def cf_avg(collection, custom_field_id)
      values = numbers(collection, custom_field_id)
      return nil if values.empty?

      (values.sum.to_f / values.size).round(2)
    end

    def cf_min(collection, custom_field_id)
      numbers(collection, custom_field_id).min
    end

    def cf_max(collection, custom_field_id)
      numbers(collection, custom_field_id).max
    end

    # Every issue below `issue`, itself excluded.
    #
    # Excluding it is what makes a subtree total expressible: a formula that
    # includes the issue it is computed on would read its own value back.
    def subtree(issue)
      return [] if issue.nil? || issue.new_record?

      unless issue.respond_to?(:descendants) && issue.respond_to?(:leaf?)
        raise AggregationError, "subtree walks issues, not #{issue.class.name}"
      end
      return [] if issue.leaf?

      records = list(issue.descendants.order(:lft))
      depth = depth_of(records)
      return records if depth <= MAX_DEPTH

      raise AggregationError,
            "the subtree of issue ##{issue.id} is #{depth} levels deep, " \
            "the limit is #{MAX_DEPTH}"
    end

    # --- internals --------------------------------------------------------

    # Normalises anything a formula may pass -- a relation, an array, a single
    # record -- into an array, refusing a collection big enough to be a table
    # scan. A relation is only read up to the cap plus one, so an oversized
    # collection is detected without loading it.
    def list(collection)
      return [] if collection.nil?
      return checked(collection.to_a) unless collection.is_a?(Array)
      return checked(collection) unless collection.respond_to?(:limit)

      checked(collection.limit(MAX_COLLECTION + 1).to_a)
    end

    def checked(items)
      return items if items.size <= MAX_COLLECTION

      raise AggregationError,
            "the collection holds more than #{MAX_COLLECTION} records, " \
            'the limit of an aggregation'
    end

    # Depth of the tree spanned by `records`, from the (lft, rgt) pairs they
    # already carry: a child opens a range that its own children fall into, so
    # a stack gives the depth in one pass without a single extra query.
    def depth_of(records)
      depth = 0
      open = []

      records.each do |record|
        open.pop while open.any? && record.lft > open.last.rgt
        open << record
        depth = open.size if open.size > depth
      end

      depth
    end

    def numbers(collection, custom_field_id)
      list(collection).filter_map do |item|
        numeric(raw_cf(item, custom_field_id))
      end
    end

    # The value as stored, before the numeric coercion `cfs` applies: an unset
    # integer field reads 0 through `cf`, which would drag an average down.
    def raw_cf(object, custom_field_id)
      raw_values_for(object)[custom_field_id.to_i]
    end

    def raw_values_for(object)
      return {} if object.nil?
      return stored_values(object) if object.id.nil?

      cached(:raw, object) { stored_values(object) }
    end

    def stored_values(object)
      object.custom_field_values.each_with_object({}) do |custom_field_value, hash|
        hash[custom_field_value.custom_field_id] = custom_field_value.value
      end
    end

    def numeric(value)
      return value if value.is_a?(Numeric)
      return nil if value.nil?

      text = value.to_s.strip
      return nil if text.empty?

      begin
        Integer(text, 10)
      rescue ArgumentError
        Float(text)
      end
    rescue ArgumentError, TypeError
      nil
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

    # Two slots: the values formulas see as `cfs`, and the raw values the
    # aggregations need. Same object, same save, read once each.
    def cached(slot, object)
      bucket = (cache[slot] ||= {})
      bucket[key_for(object)] ||= yield
    end

    def cache
      # Outside `with_cache` the values are computed on demand and thrown away:
      # a thread that evaluated one formula must not keep its objects alive.
      Thread.current[CACHE_KEY] || {}
    end

    def key_for(object)
      [object.class.name, object.id]
    end

    private_class_method :list, :checked, :depth_of, :numbers, :raw_cf,
                         :stored_values, :numeric, :cached, :cache, :key_for
  end
end
