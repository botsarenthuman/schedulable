module Schedulable
  module Model
    class Schedule  < ActiveRecord::Base

      serialize :day
      serialize :day_of_week, Hash

      belongs_to :schedulable, polymorphic: true

      attr_accessor :effective_time

      validates_presence_of :rule
      validates_presence_of :start_time
      validates_presence_of :end_time
      # validates_presence_of :date, if: Proc.new { |schedule| schedule.rule == 'singular' }
      validate :validate_day, if: Proc.new { |s| s.rule == 'weekly' }
      validate :validate_day_of_week, if: Proc.new { |s| s.rule == 'monthly' }

      def to_icecube
        return schedule_obj
      end

      def to_s
        if self.rule == 'singular'
          IceCube::Occurrence.new(self.start_time, self.end_time).to_s
        else
          schedule_obj.to_s
        end
      end

      def method_missing(meth, *args, &block)
        if schedule_obj && schedule_obj.respond_to?(meth)
          schedule_obj.send(meth, *args, &block)
        end
      end

      def self.param_names
        [:id, :start_time, :end_time, :rule, :until, :count, :interval, day: [], day_of_week: [monday: [], tuesday: [], wednesday: [], thursday: [], friday: [], saturday: [], sunday: []]]
      end

      def schedule_obj
        @schedule ||= generate_schedule
      end

      def generate_schedule        
        self.rule||= "singular"
        self.interval||= 1
        self.count||= 0

        start_time = Date.today.to_time(:utc)
        if self.start_time.present?
          start_time = start_time + self.start_time.seconds_since_midnight.seconds
        end
        start_time_string = start_time.strftime("%d-%m-%Y %I:%M %p")
        start_time = Time.zone.parse(start_time_string)

        end_time = Date.today.to_time(:utc)
        if self.end_time.present?
          end_time = end_time + self.end_time.seconds_since_midnight.seconds
        end
        end_time_string = end_time.strftime("%d-%m-%Y %I:%M %p")
        end_time = Time.zone.parse(end_time_string)

        ice_cube_schedule = IceCube::Schedule.new(start_time, end_time: end_time)

        if self.rule && self.rule != 'singular'

          self.interval = self.interval.present? ? self.interval.to_i : 1

          rule = IceCube::Rule.send("#{self.rule}", self.interval)

          if self.until
            rule.until(self.until)
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
