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

  desc 'Recompute the stored value of every computed custom field (dry run unless APPLY=true)'
  task :recompute_all => :environment do
    apply = ENV['APPLY'] == 'true'
    batch_size = ENV['BATCH_SIZE'].to_i
    batch_size = SmartCustomField::Backfill::DEFAULT_BATCH_SIZE if batch_size <= 0

    if (user_id = ENV['USER_ID'].presence)
      user = User.find_by(:id => user_id)
      abort "USER_ID=#{user_id}: no such user" if user.nil?

      User.current = user
      puts "Running as #{user.login}."
    else
      current = User.current.login.presence || 'AnonymousUser'
      puts "Running as #{current} (User.current). Set USER_ID=<id> to change it."
    end

    report = SmartCustomField::Backfill.run(:apply => apply, :batch_size => batch_size)

    report.warnings.each { |warning| puts "warning: #{warning}" }

    if report.scanned.zero?
      puts 'No object to backfill.'
    elsif apply
      puts "Scanned #{report.scanned} object(s), wrote #{report.changed} value(s), " \
           "#{report.failed} failure(s)."
    else
      puts "Scanned #{report.scanned} object(s), #{report.changed} value(s) would change. " \
           'Dry run: nothing was written. Re-run with APPLY=true to write them.'
    end

    report.errors.first(20).each { |error| puts "  - #{error}" }
    puts "  ... and #{report.errors.size - 20} more" if report.errors.size > 20
    exit 1 if report.failed.positive?
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
