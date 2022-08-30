module Schedulable
  module Model
    class Schedule  < ActiveRecord::Base

      serialize :day
      serialize :day_of_week, Hash

      belongs_to :schedulable, polymorphic: true

      attr_accessor :effective_time

      validates_presence_of :rule
      validates_presence_of :start_time
      # validates_presence_of :end_time
      # validates_presence_of :date, if: Proc.new { |schedule| schedule.rule == 'singular' }
      validate :validate_day, if: Proc.new { |s| s.rule == 'weekly' }
      validate :validate_day_of_week, if: Proc.new { |s| s.rule == 'monthly' }

      def to_icecube
        return schedule_obj
      end

      def to_s
        if self.rule == 'singular'
          IceCube::Occurrence.new(local_start_time, local_end_time).to_s
        else
          schedule_obj.to_s
        end
      end

      # The database stores the date/time as the user enters it.  However AR returns it to us in
      # the server timezone, which isn't what we want.  We therefore have methods that add the 
      # correct timezone to that time.
      # We can't store the UTC time of a class as that changes with DST - for example a 7am class
      # is really at 7am in the winter and 6am in the summer (when +1 DST applies).  IE for a given
      # class it has two UTC times depending on the time of year
      # So there are three ways to get the start time - 1) As the user sees it (db version)  2) with
      # correct timezone info on it as a ruby object  3) in UTC
      def local_start_time
        if self.timezone && start_time
          Time.find_zone(self.timezone).local(start_time.year, start_time.month, start_time.day, start_time.hour, start_time.min, start_time.sec)
        else
          start_time
        end
      end

      def local_end_time
        if self.timezone && end_time
          Time.find_zone(self.timezone).local(end_time.year, end_time.month, end_time.day, end_time.hour, end_time.min, end_time.sec)
        else
          end_time
        end
      end
      
      def local_until_time
        if self.timezone && self.until
          Time.find_zone(self.timezone).local(self.until.year, self.until.month, self.until.day, self.until.hour, self.until.min, self.until.sec)
        else
          self.until
        end
      end
      
      def local_effective_time
        if self.timezone && effective_time
          Time.find_zone(self.timezone).local(effective_time.year, effective_time.month, effective_time.day, effective_time.hour, effective_time.min, effective_time.sec)
        else
          effective_time
        end
      end

      def utc_start_time
        local_start_time.utc
      end

      def utc_end_time
        local_end_time.utc
      end
      
      def utc_until_time
        local_until_time.utc
      end
      
      def utc_effective_time
        local_effective_time.utc
      end

      def self.param_names
        [:id, :start_time, :end_time, :rule, :until, :count, :interval, day: [], day_of_week: [monday: [], tuesday: [], wednesday: [], thursday: [], friday: [], saturday: [], sunday: []]]
      end

      def schedule_obj
        @schedule ||= generate_schedule
      end

      def generate_schedule        
        self.rule     ||= "singular"
        self.interval ||= 1
        self.count    ||= 0

        # As we won't ever want to deal with historic events we start from today
        # (this improves the speed of IceCube)
        time_in_zone         = Time.find_zone(self.timezone).now
        start_time_for_today = local_start_time.change(year: time_in_zone.year, month: time_in_zone.month, day: time_in_zone.day)
        end_time_for_today   = local_end_time.change(year: time_in_zone.year, month: time_in_zone.month, day: time_in_zone.day)
        ice_cube_schedule    = IceCube::Schedule.new(start_time_for_today, end_time: end_time_for_today)

        if self.rule && self.rule != 'singular'

          self.interval = self.interval.present? ? self.interval.to_i : 1

          rule = IceCube::Rule.send("#{self.rule}", self.interval)

          if local_until_time
            rule.until(local_until_time)
          end

          if self.count && self.count.to_i > 0
            rule.count(self.count.to_i)
          end

          if self.day
            days = self.day.reject(&:empty?)
            if self.rule == 'weekly'
              days.each do |day|
                rule.day(day.to_sym)
              end
            elsif self.rule == 'monthly'
              days = {}
              day_of_week.each do |weekday, value|
                days[weekday.to_sym] = value.reject(&:empty?).map { |x| x.to_i }
              end
              rule.day_of_week(days)
            end
          end
          ice_cube_schedule.add_recurrence_rule(rule)
        end
        ice_cube_schedule
      end

      private
      # We create private methods for these to stop them being accessed outside the class
      # With the timezone returned they're incorrect and therefore should not be used other
      # than to get a time in the right zone via local_start_time
#       def start_time
#         read_attribute(:start_time)
#       end
      
#       def end_time
#         read_attribute(:end_time)
#       end
      
#       def start_time=(time)
#         write_attribute(:start_time, time)
#       end
      
#       def end_time=(time)
#         write_attribute(:end_time, time)
#       end

      def validate_day
        day.reject! { |c| c.empty? }
        if !day.any?
          errors.add(:day, :empty)
        end
      end

      def validate_day_of_week
        any = false
        day_of_week.each { |key, value|
          value.reject! { |c| c.empty? }
          if value.length > 0
            any = true
            break
          end
        }
        if !any
          errors.add(:day_of_week, :empty)
        end
      end
    end
  end
end
