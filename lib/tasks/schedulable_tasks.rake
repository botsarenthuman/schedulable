require 'rake'
namespace :schedulable do

  desc 'prints the names of the schedulable types'
  task show_schedulables: :environment do
    Schedule.all.uniq.pluck(:schedulable_type).each do |schedulable_type|
      puts schedulable_type
    end
  end

  desc 'Builds occurrences for schedulable models'
  task build_occurrences: :environment do
    Schedule.all.uniq.pluck(:schedulable_type).each do |schedulable_type|
      clazz = schedulable_type.constantize
      occurrences_associations = Schedulable::ActsAsSchedulable.occurrences_associations_for(clazz)
      occurrences_associations.each do |association|
        clazz.send("build_" + association.to_s)
      end
    end
  end
end
