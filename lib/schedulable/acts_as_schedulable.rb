module Schedulable
  module ActsAsSchedulable
    extend ActiveSupport::Concern

    included do
    end

    module ClassMethods

      attr_accessor :effective_date

      def acts_as_schedulable(name, options = {})
        name ||= :schedule

        # setting up an effective_date field in the model
        arg = 'effective_date'
        # getter
        class_eval("def #{arg};@#{arg};end")
        # setter
        class_eval("def #{arg}=(val);@#{arg}=val;end")

        has_one name, as: :schedulable, dependent: :destroy, class_name: 'Schedule'
        accepts_nested_attributes_for name

        if options[:occurrences]
          # setup association
          if options[:occurrences].is_a?(String) || options[:occurrences].is_a?(Symbol)
            occurrences_association = options[:occurrences].to_sym
            options[:occurrences] = {}
          else
            occurrences_association = options[:occurrences][:name]
            options[:occurrences].delete(:name)
          end
          options[:occurrences][:class_name] = occurrences_association.to_s.classify
          options[:occurrences][:as] ||= :schedulable
          options[:occurrences][:dependent] || :destroy
          options[:occurrences][:autosave] ||= true

          has_many occurrences_association, options[:occurrences]

          # table_name
          occurrences_table_name = occurrences_association.to_s.tableize

          # remaining
          remaining_occurrences_options = options[:occurrences].clone
          remaining_occurrences_association = ('remaining_' << occurrences_association.to_s).to_sym
          has_many remaining_occurrences_association, -> { where("#{occurrences_table_name}.date >= ?", Time.zone.now.to_date).order('date ASC') }, remaining_occurrences_options

          # previous
          previous_occurrences_options = options[:occurrences].clone
          previous_occurrences_association = ('previous_' << occurrences_association.to_s).to_sym
          has_many previous_occurrences_association, -> { where("#{occurrences_table_name}.date < ?", Time.zone.now.to_date).order('date DESC') }, previous_occurrences_options

          ActsAsSchedulable.add_occurrences_association(self, occurrences_association)

          after_save "build_#{occurrences_association}".to_sym

          self.class.instance_eval do
            define_method("build_#{occurrences_association}") do
              # build occurrences for all events
              # TODO: only invalid events
              schedulables = all
              schedulables.each { |schedulable| schedulable.send("build_#{occurrences_association}") }
            end
          end

          define_method "build_#{occurrences_association}_after_update" do
            schedule = send(name)
            send("build_#{occurrences_association}") if schedule.changes.any?
          end

          define_method "build_#{occurrences_association}" do

            # build occurrences for events
            schedule = send(name)

            if schedule.present?
              now = Time.zone.now

              # all events changes will be made from this date on
              effective_date_for_changes = effective_date.nil? ? now : effective_date

              schedulable = schedule.schedulable
              terminating = schedule.rule != 'singular' && (schedule.until.present? || schedule.count.present? && schedule.count > 1)

              max_period = Schedulable.config.max_build_period || 1.year
              max_date = now + max_period

              max_date = terminating ? [max_date, schedule.last.to_time].min : max_date

              max_count = Schedulable.config.max_build_count || 100
              max_count = terminating && schedule.remaining_occurrences.any? ? [max_count, schedule.remaining_occurrences.count].min : max_count

              if schedule.rule != 'singular'
                # Get schedule occurrences
                all_occurrences = schedule.occurrences_between(effective_date_for_changes.beginning_of_day, max_date.to_time)

                occurrences = []
                # Filter valid dates
                all_occurrences.each_with_index do |occurrence_date, index|
                  if occurrence_date.present? && occurrence_date.to_time > effective_date_for_changes
                    if occurrence_date.to_time < max_date && (index <= max_count || max_count <= 0)
                      occurrences << occurrence_date
                    else
                      max_date = [max_date, occurrence_date].min
                    end
                  end
                end
              else
                # Get Singular occurrence
                d = schedule.date
                t = schedule.start_time
                # dt = d + t.seconds_since_midnight.seconds
                singular_date_time = (d + t.seconds_since_midnight.seconds).to_datetime
                occurrences = [singular_date_time]
              end

              # Build occurrences
              update_mode = Schedulable.config.update_mode || :datetime

              # Always use index as base for singular events
              update_mode = :index if schedule.rule == 'singular'

              # Get existing remaining records
              occurrences_records = schedulable.send("remaining_#{occurrences_association}")
              # occurrences_records = schedulable.send("#{occurrences_association}").where('date >= ?', effective_date_for_changes)

              # build occurrences
              occurrences.each_with_index do |occurrence, index|
                # Pull an existing record
                if update_mode == :index
                  existing_records = [occurrences_records[index]]
                elsif update_mode == :datetime
                  existing_records = occurrences_records.select do |record|
                    record.date == occurrence.to_date &&
                    record.start_time.hour == occurrence.start_time.hour &&
                    record.start_time.min == occurrence.start_time.min &&
                    record.end_time.hour == occurrence.end_time.hour &&
                    record.end_time.min == occurrence.end_time.min
                    # record.date.to_datetime == occurrence.to_datetime
                  end
                else
                  existing_records = []
                end

                start_time = schedule.rule == 'singular' ? occurrence : occurrence.start_time
                end_time = schedule.rule == 'singular' ? occurrence : occurrence.end_time

                # fields that are going to be extracted from the schedulable
                # and copied over to the occurrence. these should be configured
                # at the model
                schedulable_fields = options[:schedulable_fields] || {}

                # extracting the fields to copy them over
                data = schedulable_fields.reduce({}) do |acum, f|
                  acum[f] = self.send(f)
                  acum
                end

                occurrence_data = data.merge(date: occurrence.to_date, start_time: start_time, end_time: end_time)

                if existing_records.any?
                  # Overwrite existing records
                  existing_records.each do |existing_record|
                    unless existing_record.update!(occurrence_data)
                      puts 'An error occurred while saving an existing occurrence record'
                    end
                  end
                else
                  unless occurrences_records.create!(occurrence_data)
                    puts 'An error occurred while creating an occurrence record'
                  end
                end
              end

              # Clean up unused remaining occurrences
              occurrences_records = schedulable.send("remaining_#{occurrences_association}")

              record_count = 0
              destruction_list = occurrences_records.select do |occurrence_record|
                event_time = occurrence_record
                  .date.to_time.utc
                  .change(hour: occurrence_record.start_time.hour, min: occurrence_record.start_time.min)

                mark_for_destruction = schedule.rule != 'singular' &&
                  (occurrence_record.date >= effective_date_for_changes.to_date) &&
                  (!schedule.occurs_on?(event_time) ||
                  !schedule.occurring_at?(event_time) ||
                  occurrence_record.date > max_date) ||
                  schedule.rule == 'singular' && record_count > 0

                # byebug if mark_for_destruction

                mark_for_destruction = (event_time > now) && mark_for_destruction
                record_count += 1

                mark_for_destruction
              end

              destruction_list.each(&:destroy)

            end
          end
        end
      end
    end

    def self.occurrences_associations_for(clazz)
      @@schedulable_occurrences ||= []
      @@schedulable_occurrences.select do |item|
        item[:class] == clazz
      end.map do |item|
        item[:name]
      end
    end

    def self.add_occurrences_association(clazz, name)
      @@schedulable_occurrences ||= []
      @@schedulable_occurrences << { class: clazz, name: name }
    end
  end
end
ActiveRecord::Base.send :include, Schedulable::ActsAsSchedulable
