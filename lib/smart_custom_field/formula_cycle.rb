# frozen_string_literal: true

module SmartCustomField
  # Detects dependency cycles between computed custom fields of the same type.
  #
  # A formula reads other fields through `cfs[<id>]`, so field A depends on
  # field B as soon as A's formula mentions B. When B also depends on A,
  # directly or through a longer chain, no value can be computed first:
  #
  #   field 1: cfs[2] + 1
  #   field 2: cfs[1] * 2     # 1 -> 2 -> 1
  #
  # Nothing loops forever at save time, because `cfs` is built from the values
  # stored *before* the recompute, but each field then reads the previous save
  # of the other: the pair drifts one save behind itself forever and no value
  # ever settles. Flagging the loop at save time is the only moment the mistake
  # is still visible to the person who wrote it.
  #
  # The graph is limited to the fields of one customized class. `cfs[...]` only
  # ever resolves inside the object being computed, so a cross-object read
  # (`cf(project, 12)`) can never close a loop within it.
  module FormulaCycle
    module_function

    # Cycle `field` would take part in if it were saved with `source`, as the
    # list of custom field ids running from `field` back to itself
    # ([1, 2, 1] for 1 -> 2 -> 1), or nil when the formula is acyclic.
    #
    # `field` must be persisted: a field that does not exist yet has no id, and
    # no other formula can reference it, so it cannot close a loop.
    def detect(field, source)
      return nil if field.nil? || field.id.nil?

      find_cycle(graph_for(field, source), field.id)
    end

    # Same check against the formula currently stored in the database. Lets the
    # caller tell a cycle this save would introduce from one the installation
    # already carries, which must keep saving.
    def stored_cycle(field)
      return nil if field.nil? || field.id.nil? || !field.persisted?

      detect(field, field.formula_was)
    end

    # Ids of the computed fields of `field`'s class, mapped to the ids their
    # formula reads. `source` replaces the formula of `field` itself so the
    # graph describes what the record is about to become, not what is stored.
    def graph_for(field, source)
      fields = CustomField.where(:type => field.type, :is_computed => true).to_a
      known = fields.map(&:id)

      fields.each_with_object({}) do |other, graph|
        formula = other.id == field.id ? source : other.formula
        graph[other.id] = Evaluator.custom_field_ids(formula) & known
      end
    end

    # Depth-first search from `start` back to `start`, returning the path
    # walked with `start` repeated at both ends, or nil.
    def find_cycle(graph, start)
      search(graph, start, start, [start], { start => true })
    end

    def search(graph, node, target, path, visited)
      Array(graph[node]).each do |successor|
        return path + [successor] if successor == target
        next if visited[successor]

        # A node that cannot reach the target from here cannot reach it from
        # anywhere else either, so it is never revisited: the search stays
        # linear in the number of fields even on a dense graph.
        visited[successor] = true
        found = search(graph, successor, target, path + [successor], visited)
        return found if found
      end
      nil
    end

    private_class_method :graph_for, :find_cycle, :search
  end
end
