module Schedulable
  module ActsAsSchedulable
    extend ActiveSupport::Concern

    included do
    end

    module ClassMethods

      def set_up_accessor(arg)
        # getter
        class_eval("def #{arg};@#{arg};end")
        # setter
        class_eval("def #{arg}=(val);@#{arg}=val;end")
      end

      def acts_as_schedulable(name, options = {})
        name ||= :schedule

        # var to store occurrences with errors
        set_up_accessor('occurrences_with_errors')

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
          options[:occurrences][:dependent] ||= :destroy
          options[:occurrences][:autosave] ||= true

          has_many occurrences_association, options[:occurrences]

          # table_name
          occurrences_table_name = occurrences_association.to_s.tableize

          # remaining
          remaining_occurrences_options = options[:occurrences].clone
          remaining_occurrences_association = ('remaining_' << occurrences_association.to_s).to_sym
          has_many remaining_occurrences_association, -> { where("#{occurrences_table_name}.start_time >= ?", Time.zone.now.to_datetime).order('start_time ASC') }, remaining_occurrences_options

          # previous
          previous_occurrences_options = options[:occurrences].clone
          previous_occurrences_association = ('previous_' << occurrences_association.to_s).to_sym
          has_many previous_occurrences_association, -> { where("#{occurrences_table_name}.start_time < ?", Time.zone.now.to_datetime).order('start_time DESC') }, previous_occurrences_options

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
              # Set dates change will be effective from
              now = Time.zone.now
              effective_time_for_changes = schedule.local_effective_time.nil? ? now : schedule.local_effective_time
              
              # Store details about schedulable
              schedulable = schedule.schedulable
              terminating = schedule.rule != 'singular' && (schedule.until.present? || schedule.count.present? && schedule.count > 1)
              self.occurrences_with_errors = [] if self.occurrences_with_errors.nil?

              # Set the max date to go till
              max_period = Schedulable.config.max_build_period || 1.year
              max_time = (now + max_period).to_time
              max_time = terminating ? [max_time, schedule.to_icecube.last.start_time].min : max_time

              # Generate the start times of the occurrences
              if schedule.rule == 'singular'
                occurrences = [IceCube::Occurrence.new(schedule.local_start_time, schedule.local_end_time)]
              else
                # Get schedule occurrences
                all_occurrences = schedule.to_icecube.occurrences_between(effective_time_for_changes, max_time)

                occurrences = []
                # Filter valid dates
                all_occurrences.each_with_index do |occurrence_item, index|
                  if occurrence_item.present? && occurrence_item.start_time >= effective_time_for_changes
                    if occurrence_item.start_time <= max_time
                      occurrences << occurrence_item
                    else
                      max_time = [max_time, occurrence_item.start_time].min
                    end
                  end
                end
              end
              
              # Determine update mode
              update_mode = Schedulable.config.update_mode || :datetime
              update_mode = :index if schedule.rule == 'singular'

              # Get existing remaining records
              occurrences_records = schedulable.send("remaining_#{occurrences_association}")
              
              # Fields that are going to be extracted from the schedulable
              # and copied over to the occurrence. these should be configured
              # at the model
              schedulable_fields = options[:schedulable_fields] || {}
              schedulable_fields_data = schedulable_fields.reduce({}) do |acum, f|
                acum[f] = self.send(f)
                acum
              end

              # Save occurrences that should be in our database. Bear in mind there's two cases
              # here - a new generation with no existing records and an update
              # var occurrences is what the schedule should be
              # var occurrences_records stores actual DB records
              occurrences.each_with_index do |occurrence, index|
                if update_mode == :index
                  if schedule.rule == 'singular'
                    # remaining_#{occurrences_association} doesn't work for singular events
                    existing_records = [schedulable.send(occurrences_association).first]
                  else
                    existing_records = [occurrences_records[index]]
                  end
                elsif update_mode == :datetime
                  existing_records = occurrences_records.select do |record|
                    record.start_time == occurrence
                  end
                else
                  existing_records = []
                end
                
                # Merge with start/end time
                occurrence_data = schedulable_fields_data.merge(start_time: occurrence.start_time, end_time: occurrence.end_time)

                # Create/Update records
                if existing_records.any?
                  existing_records.each do |existing_record|
                    existing_record.update_from_schedulable = true
                    self.occurrences_with_errors << existing_record unless existing_record.update(occurrence_data)
                  end
                else
                  new_record = occurrences_records.build(occurrence_data)
                  self.occurrences_with_errors << new_record unless new_record.save
                end
              end
        
              # Re-load the records as we've created new ones
              occurrences_records = schedulable.send("remaining_#{occurrences_association}")

              # Remove no-longer needed records
              record_count = 0
              destruction_list = occurrences_records.select do |occurrence_record|
                # Note no_longer_relevant uses cached occurrences as it's more efficient
                event_time         = occurrence_record.start_time
                event_in_future    = event_time > effective_time_for_changes
                no_longer_relevant = !occurrences.include?(event_time) ||
                                     occurrence_record.start_time > max_time
                if schedule.rule == 'singular' && record_count > 0
                  mark_for_destruction = event_in_future
                elsif schedule.rule != 'singular' && no_longer_relevant
                  mark_for_destruction = event_in_future
                else
                  mark_for_destruction = false
                end
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
