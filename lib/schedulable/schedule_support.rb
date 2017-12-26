module Schedulable

  module ScheduleSupport

    def self.param_names
      [:id, :start_time, :end_time, :rule, :until, :count, :interval, :effective_date, day: [], day_of_week: [monday: [], tuesday: [], wednesday: [], thursday: [], friday: [], saturday: [], sunday: []]]
    end

  end
end
