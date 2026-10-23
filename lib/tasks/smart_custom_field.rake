# frozen_string_literal: true

namespace :smart_custom_field do
  desc 'Export computed custom field formulas to a JSON file'
  task :export, [:file] => :environment do |_task, args|
    file = args[:file].presence || ENV['FILE'].presence ||
           File.join(Rails.root, 'config', 'smart_custom_field_formulas.json')

    data = SmartCustomField::FormulaExport.write_to(file)
    count = data['custom_fields'].size
    puts "Exported #{count} computed custom field(s) to #{file}"
  end

  desc 'Import computed custom field formulas from a JSON file (dry run unless APPLY=true)'
  task :import, [:file] => :environment do |_task, args|
    file = args[:file].presence || ENV['FILE'].presence
    if file.blank?
      abort 'Usage: rake smart_custom_field:import[path/to/formulas.json] (add APPLY=true to write)'
    end

    report = SmartCustomField::FormulaExport.import(file, :write => ENV['APPLY'] == 'true')

    if report.changes.empty?
      puts 'No difference: the file and the database agree.'
    else
      puts "#{report.changes.size} difference(s):"
      report.changes.each { |change| puts "  #{change}" }
    end

    if report.written
      report.results.reject { |result| result.status == :applied }.each do |result|
        puts "  [#{result.status}] #{result.message}"
      end
      puts "Applied #{report.applied.size} change(s), #{report.failed.size} failure(s)."
      exit 1 if report.failed.any?
    else
      puts 'Dry run: nothing was written. Re-run with APPLY=true to write the formulas above.'
    end
  end

  desc 'Check every computed formula and report what would break (advisory)'
  task :check => :environment do
    fields = CustomField.where(:is_computed => true).order(:id)
    flagged = 0

    fields.each do |field|
      result = SmartCustomField::StaticAnalyzer.for_field(field)
      warnings = result.warnings
      unknown = SmartCustomField::StaticAnalyzer.unknown_references(field)
      warnings << "unknown custom field id(s): #{unknown.join(', ')}" if unknown.any?
      next if warnings.empty?

      flagged += 1
      puts "##{field.id} #{field.name} (#{field.type})"
      warnings.each { |warning| puts "  - #{warning}" }
      puts "  formula: #{field.formula.inspect}"
    end

    if flagged.zero?
      puts "#{fields.size} computed field(s), no problem found."
    else
      puts "#{flagged} of #{fields.size} computed field(s) need attention."
    end
  end
end
