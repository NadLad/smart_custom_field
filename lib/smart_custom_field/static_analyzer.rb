# frozen_string_literal: true

require 'ripper'

module SmartCustomField
  # Inspects a formula without running it.
  #
  # The validator evaluates a formula against a blank instance, where every
  # optional attribute is nil. `estimated_hours * 2` raises NoMethodError on nil
  # and that error is deliberately ignored, so a typo hidden behind a nil
  # association (`project.estimted_hours`) slips through: the receiver is nil,
  # the NoMethodError looks exactly like the expected one. Walking the parse
  # tree catches it without executing anything.
  #
  # This is ADVISORY ONLY. Nothing here blocks a save: a false positive must
  # never make a working formula impossible to re-save.
  module StaticAnalyzer
    # Methods a formula may call without a receiver that are not defined on the
    # customized model: the plugin's own helpers (see FormulaHelpers).
    HELPER_METHODS = %w[cfs cf].freeze

    Result = Struct.new(:source, :syntax_error, :unknown_methods, :referenced_ids,
                        :uses_current_user, :reads_related_objects,
                        keyword_init: true) do
      def valid_syntax?
        syntax_error.nil?
      end

      # True when the formula only reads the object it runs against (its own
      # attributes and the `cfs` values handed to it). A formula that reads
      # another record -- `project.name`, `parent.cfs[5]` -- can produce a
      # different result without the object itself being saved.
      def self_contained?
        valid_syntax? && !uses_current_user && !reads_related_objects
      end

      def warnings
        list = []
        list << "syntax error: #{syntax_error}" if syntax_error
        unknown_methods.each do |name|
          list << "unknown method `#{name}` on the customized object"
        end
        if uses_current_user
          list << 'reads User.current, which is AnonymousUser outside a request ' \
                   '(rake task, import): the result would differ from a real save'
        end
        list
      end
    end

    module_function

    # `model_class` is the class the formula runs against (Issue, Project...).
    # Pass nil when it is unknown: the method check is then skipped rather than
    # reported against the wrong class.
    def analyze(source, model_class = nil)
      source = source.to_s
      tree = Ripper.sexp(source)

      if tree.nil?
        return Result.new(
          :source => source,
          :syntax_error => syntax_error_message(source),
          :unknown_methods => [],
          :referenced_ids => Evaluator.custom_field_ids(source),
          :uses_current_user => uses_current_user?(source),
          :reads_related_objects => false
        )
      end

      unknown = []
      flags = { :user_current => false, :related => false }
      walk(tree, unknown, flags, model_class)

      Result.new(
        :source => source,
        :syntax_error => nil,
        :unknown_methods => unknown.uniq.sort,
        :referenced_ids => Evaluator.custom_field_ids(source),
        :uses_current_user => flags[:user_current],
        :reads_related_objects => flags[:related]
      )
    end

    # Convenience wrapper for a CustomField record.
    def for_field(record)
      analyze(record.formula, record.class.customized_class)
    end

    # Custom field ids referenced by the formula that the record's own type does
    # not carry. The validator already refuses them at save time; this reports
    # them for fields that predate the validator.
    def unknown_references(record)
      ids = Evaluator.custom_field_ids(record.formula)
      return [] if ids.empty?

      known = CustomField.where(:id => ids, :type => record.type).pluck(:id)
      ids - known
    end

    # --- internals --------------------------------------------------------

    def walk(node, unknown, flags, model_class)
      return unless node.is_a?(Array)

      case node[0]
      when :vcall, :fcall, :command
        check_bare_call(node, unknown, flags, model_class)
      when :call
        check_qualified_call(node, unknown, flags, model_class)
      end

      node.each { |child| walk(child, unknown, flags, model_class) }
    end

    # A call without a receiver runs against `self`, which is the customized
    # object itself.
    def check_bare_call(node, unknown, flags, model_class)
      name = ident_name(node[1])
      return if name.nil?

      # A bare `project` is an association, not one of the object's own
      # attributes: what it points at changes without this object being
      # touched.
      if model_class && association_class(model_class, name)
        flags[:related] = true
        return
      end

      return if known_method?(name, model_class)

      unknown << name
    end

    def check_qualified_call(node, unknown, flags, model_class)
      name = call_name(node)
      return if name.nil?

      receiver = node[1]
      if const_receiver(receiver) == 'User' && name == 'current'
        flags[:user_current] = true
        return
      end

      # `self.project.name` reads another record just as much as `project.name`
      # does, and the bare call is not visited in that form.
      if model_class && self_receiver?(receiver) && association_class(model_class, name)
        flags[:related] = true
      end

      # The receiver's class is only known for `self` and for an association
      # chain; anything else (`cfs[1].to_s`, a local variable) is left alone.
      klass = receiver_class(receiver, model_class)
      return if klass.nil? || known_method?(name, klass)

      unknown << name
    end

    # Resolves the class of a receiver expression, one association at a time:
    # `self` -> model, `project` -> Project, `parent.project` -> Project.
    # Returns nil as soon as the type cannot be determined.
    def receiver_class(node, model_class)
      return nil if model_class.nil? || !node.is_a?(Array)
      return model_class if self_receiver?(node)

      case node[0]
      when :vcall
        name = ident_name(node[1])
        name.nil? ? nil : association_class(model_class, name)
      when :call
        name = call_name(node)
        parent = receiver_class(node[1], model_class)
        return nil if name.nil? || parent.nil?

        association_class(parent, name)
      end
    end

    def association_class(model_class, name)
      return nil unless model_class.respond_to?(:reflect_on_association)

      reflection = model_class.reflect_on_association(name.to_sym)
      reflection&.klass
    rescue StandardError
      nil
    end

    # `a.b` parses as [:call, receiver, [:@period, "."], [:@ident, "b"]]: the
    # method name is at index 3 when the separator is a :@period / :@op, and at
    # index 2 for the `a.b = 1` setter form.
    def call_name(node)
      [node[3], node[2]].each do |candidate|
        name = ident_name(candidate)
        return name if name
      end
      nil
    end

    def ident_name(node)
      return nil unless node.is_a?(Array)

      node[0] == :@ident ? node[1] : nil
    end

    def self_receiver?(node)
      return false unless node.is_a?(Array) && node[0] == :var_ref

      inner = node[1]
      inner.is_a?(Array) && inner[0] == :@kw && inner[1] == 'self'
    end

    def const_receiver(node)
      return nil unless node.is_a?(Array) && node[0] == :var_ref

      inner = node[1]
      inner.is_a?(Array) && inner[0] == :@const ? inner[1] : nil
    end

    def known_method?(name, model_class)
      return true if HELPER_METHODS.include?(name)
      # Kernel and ActiveSupport's Object core extensions (blank?, presence, try).
      return true if Object.method_defined?(name) || Object.private_method_defined?(name)
      return true if model_class.nil?

      model_class.new.respond_to?(name, true)
    end

    def uses_current_user?(source)
      source.match?(/\bUser\s*\.\s*current\b/)
    end

    def syntax_error_message(source)
      if defined?(RubyVM::AbstractSyntaxTree)
        begin
          RubyVM::AbstractSyntaxTree.parse(source)
          'unparsable'
        rescue SyntaxError => e
          e.message.lines.first.to_s.strip
        end
      else
        'unparsable'
      end
    end
  end
end
