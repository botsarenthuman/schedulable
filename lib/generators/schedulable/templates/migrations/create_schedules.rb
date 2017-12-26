class CreateSchedules < ActiveRecord::Migration[5.1]
  def self.up
    create_table :schedules do |t|
      t.references :schedulable, polymorphic: true

      t.datetime :start_time
      t.datetime :end_time

      t.string :rule
      t.string :interval

      t.text :day
      t.text :day_of_week

      t.datetime :until
      t.integer :count

      t.timestamps
    end
  end

  def self.down
    drop_table :schedules
  end
end
