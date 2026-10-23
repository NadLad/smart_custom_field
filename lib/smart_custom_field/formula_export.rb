# frozen_string_literal: true

require 'json'

module SmartCustomField
  # Reads and writes the computed custom field formulas as JSON, so they can be
  # versioned in git and moved between environments (development -> production).
  #
  # Only `formula` is ever written. `is_computed` cannot change after creation
  # (see CustomFieldPatch) and `name` / `field_format` are exported for
  # readability and to spot a field that drifted between two environments, never
  # to overwrite it. A field declared in the file but absent locally is never
  # created, and a computed field absent from the file is never deleted: both
  # are reported and skipped.
  module FormulaExport
    FORMAT_VERSION = 1

    # One difference between the file and the database.
    #   :updated  both sides have the field, the formula differs
    #   :added    the file declares an id that does not exist locally
    #   :removed  a computed field exists locally but is absent from the file
    Change = Struct.new(:action, :id, :name, :from_formula, :to_formula, keyword_init: true) do
      def to_s
        case action
        when :updated
          "~ ##{id} #{name}: #{from_formula.inspect} -> #{to_formula.inspect}"
        when :added
          "+ ##{id} #{name}: declared in the file, unknown locally (skipped)"
        when :removed
          "- ##{id} #{name}: computed locally, absent from the file (kept)"
        end
      end
    end

    # Outcome of writing one change. `status` is :applied, :failed or :skipped.
    Result = Struct.new(:change, :status, :message, keyword_init: true)

    Report = Struct.new(:changes, :results, :written, keyword_init: true) do
      def applied
        results.select { |result| result.status == :applied }
      end

      def failed
        results.select { |result| result.status == :failed }
      end
    end

    module_function

    def dump
      {
        'format_version' => FORMAT_VERSION,
        'exported_at' => Time.now.utc.iso8601,
        'custom_fields' => computed_fields.map { |field| attributes_of(field) }
      }
    end

    # Writes the JSON document to `path` and returns the dumped data.
    def write_to(path)
      data = dump
      File.write(path, "#{JSON.pretty_generate(data)}\n")
      data
    end

    # Returns the `custom_fields` array of the file, after checking the format.
    def read(path)
      data = JSON.parse(File.read(path))
      version = data['format_version']
      unless version == FORMAT_VERSION
        raise ArgumentError,
              "unsupported format_version #{version.inspect} (expected #{FORMAT_VERSION})"
      end

      fields = data['custom_fields']
      raise ArgumentError, 'no custom_fields array in the file' unless fields.is_a?(Array)

      fields
    end

    # Compares the file with the database. Nothing is written.
    def diff(exported)
      local = computed_fields.index_by(&:id)
      seen = {}

      changes = exported.filter_map do |entry|
        id = entry['id'].to_i
        seen[id] = true
        field = local[id]
        if field.nil?
          Change.new(:action => :added, :id => id,
                     :name => entry['name'], :from_formula => nil, :to_formula => entry['formula'])
        elsif field.formula.to_s != entry['formula'].to_s
          Change.new(:action => :updated, :id => id, :name => field.name,
                     :from_formula => field.formula, :to_formula => entry['formula'])
        end
      end

      local.each do |id, field|
        next if seen[id]

        changes << Change.new(:action => :removed, :id => id, :name => field.name,
                              :from_formula => field.formula, :to_formula => nil)
      end

      changes.sort_by { |change| [change.id.to_i, change.action.to_s] }
    end

    # Writes the formula of every :updated change. Everything else is skipped on
    # purpose: see the module comment.
    def apply_changes(changes)
      changes.map do |change|
        if change.action == :updated
          write_change(change)
        else
          Result.new(:change => change, :status => :skipped, :message => change.to_s)
        end
      end
    end

    # Reads `path`, diffs it against the database and, when `write` is true,
    # applies the formula changes. Dry run by default: the caller has to opt in
    # explicitly, so a mistyped import cannot rewrite production formulas.
    def import(path, write: false)
      changes = diff(read(path))
      results = write ? apply_changes(changes) : []
      Report.new(:changes => changes, :results => results, :written => write)
    end

    def write_change(change)
      field = CustomField.find_by(:id => change.id)
      if field.nil?
        return Result.new(:change => change, :status => :failed, :message => 'custom field not found')
      end

      field.formula = change.to_formula
      field.save!
      Result.new(:change => change, :status => :applied, :message => change.to_s)
    rescue ActiveRecord::RecordInvalid => e
      Result.new(:change => change, :status => :failed,
                 :message => e.record.errors.full_messages.join(', '))
    end

    def computed_fields
      CustomField.where(:is_computed => true).order(:id).to_a
    end

    def attributes_of(field)
      {
        'id' => field.id,
        'name' => field.name,
        'type' => field.type,
        'field_format' => field.field_format,
        'formula' => field.formula,
        'is_computed' => field.is_computed?
      }
    end
  end
end
