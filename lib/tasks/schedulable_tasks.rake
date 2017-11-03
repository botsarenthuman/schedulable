require 'rake'
desc 'Builds occurrences for schedulable models'
namespace :schedulable do
  task test: :environment do
    puts 'test of schedulable'
    Schedule.count
    Schedule.uniq.pluck(:schedulable_type).each do |schedulable_type|
      puts schedulable_type
    end
  end

  task :build_occurrences => :environment do
    Schedule.uniq.pluck(:schedulable_type).each do |schedulable_type|
      clazz = schedulable_type.constantize
      occurrences_associations = Schedulable::ActsAsSchedulable.occurrences_associations_for(clazz)
      occurrences_associations.each do |association|
        clazz.send("build_" + association.to_s)
      end
    end
  end
end
