require "../spec_helper"

module ConnectionPoolSpec
  extend self

  @@count = 0_i64

  def self.reinit
    reinit_migration_manager
  end

  describe "Clear::SQL" do
    describe "ConnectionPool" do
      it "handle multiple fibers" do
        begin
          Clear::SQL.execute("CREATE TABLE tests (id serial PRIMARY KEY)")

          init = true
          spawn do
            Clear::SQL.transaction do
              Clear::SQL.insert("tests", {id: 1}).execute
              sleep 200.milliseconds # < The transaction is not yet commited
            end
          end

          @@count = 0

          spawn do
            # Not inside the transaction so count must be zero since the transaction is not finished:
            sleep 100.milliseconds
            @@count = Clear::SQL.select.from("tests").count
          end

          sleep 300.milliseconds # Let the 2 spawn finish...

          @@count.should eq 0 # < If one, the connection pool got wrong with the fiber.

          # Now the transaction is over, count should be 1
          count = Clear::SQL.select.from("tests").count
          count.should eq 1
        ensure
          Clear::SQL.execute("DROP TABLE tests;") unless init
        end
      end
    end
  end
end
