require "../spec_helper"

module IntervalSpec
  class IntervalMigration78392
    include Clear::Migration

    def change(dir)
      create_table(:interval_table) do |t|
        t.column :interval, :interval, null: true
        t.column :time_in_date, :time, null: true

        t.timestamps
      end
    end
  end

  def self.reinit!
    reinit_migration_manager
    IntervalMigration78392.new.apply
  end

  class IntervalModel
    include Clear::Model

    primary_key

    self.table = "interval_table"

    column interval : Clear::Interval?
    column time_in_date : Clear::TimeInDay?
  end

  describe Clear::Interval do
    it "be saved into database (and converted to pg interval type)" do
      temporary do
        reinit!

        3.times do |id|
          months = Random.rand(-1000..1000)
          days = Random.rand(-1000..1000)
          microseconds = Random.rand(-10_000_000..10_000_000)

          interval = Clear::Interval.new(months: months, days: days, microseconds: microseconds)
          IntervalModel.create! id: id, interval: interval

          record = IntervalModel.find! id
          record.interval.not_nil!.months.should eq months
          record.interval.not_nil!.days.should eq days
          record.interval.not_nil!.microseconds.should eq microseconds
        end
      end
    end

    it "be added and substracted to a date" do
      # TimeSpan
      [1.hour, 1.day, 1.month].each do |span|
        i = Clear::Interval.new(span)
        now = Time.local

        (now + i).to_unix.should eq((now + span).to_unix)
        (now - i).to_unix.should eq((now - span).to_unix)
      end

      i = Clear::Interval.new(months: 1, days: -1, minutes: 12)
      now = Time.local

      (now + i).to_unix.should eq((now + 1.month - 1.day + 12.minute).to_unix)
      (now - i).to_unix.should eq((now - 1.month + 1.day - 12.minute).to_unix)
    end

    it "be used in expression engine" do
      IntervalModel.query.where {
        (created_at - Clear::Interval.new(months: 1)) > updated_at
      }.to_sql.should eq %(SELECT * FROM "interval_table" WHERE (("created_at" - INTERVAL '1 months') > "updated_at"))
    end

    it "be casted into string" do
      Clear::Interval.new(months: 1, days: 1).to_sql.to_s.should eq("INTERVAL '1 months 1 days'")
    end
  end

  describe Clear::TimeInDay do
    it "be parsed" do
      value = 12i64 * 3_600 + 50*60
      Clear::TimeInDay.parse("12:50").microseconds.should eq(value * 1_000_000)

      Clear::TimeInDay.parse("12:50:02").microseconds.should eq((value + 2) * 1_000_000)

      wrong_formats = {"a:21", ":32:54", "12345", "0:0:0"}

      wrong_formats.each do |format|
        expect_raises(Exception, /wrong format/i) { Clear::TimeInDay.parse(format) }
      end
    end

    it "be saved into database and converted" do
      temporary do
        reinit!

        time_in_date = "12:32"
        record = IntervalModel.create! time_in_date: time_in_date
        record.time_in_date.not_nil!.to_s(show_seconds: false).should eq("12:32")
        record.time_in_date = record.time_in_date.not_nil! + 12.minutes
        record.save!

        record.reload.time_in_date.to_s.should eq("12:44:00")
      end
    end
  end
end
