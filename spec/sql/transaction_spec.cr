require "spec"

require "../spec_helper"

module TransactionSpec
  extend self

  def with_session_isolation(isolation : String, &)
    Lustra::SQL::ConnectionPool.with_connection("default") do |connection|
      previous_isolation = connection.query_one("SHOW default_transaction_isolation", as: String)

      begin
        connection.query_one("SELECT set_config('default_transaction_isolation', $1, false)", isolation, as: String)
        yield
      ensure
        connection.query_one("SELECT set_config('default_transaction_isolation', $1, false)", previous_isolation, as: String)
      end
    end
  end

  describe "Lustra::SQL::Transaction#transaction" do
    {
      {Lustra::SQL::Transaction::Level::ReadCommitted, "read committed", "repeatable read"},
      {Lustra::SQL::Transaction::Level::RepeatableRead, "repeatable read", "read committed"},
      {Lustra::SQL::Transaction::Level::Serializable, "serializable", "read committed"},
    }.each do |level, expected_isolation, session_isolation|
      it "uses #{level} isolation instead of the session default" do
        with_session_isolation(session_isolation) do
          Lustra::SQL.transaction(level: level) do |connection|
            connection.query_one("SHOW transaction_isolation", as: String).should eq(expected_isolation)
          end
        end
      end
    end

    it "uses the declared Serializable default when no level is supplied" do
      with_session_isolation("read committed") do
        Lustra::SQL.transaction do |connection|
          connection.query_one("SHOW transaction_isolation", as: String).should eq("serializable")
        end
      end
    end

    it "create transactional block" do
      Lustra::SQL.transaction { Lustra::SQL.select("1").execute }
      Lustra::SQL.transaction(level: Lustra::SQL::Transaction::Level::ReadCommitted) { Lustra::SQL.select("1").execute }
      Lustra::SQL.transaction(level: Lustra::SQL::Transaction::Level::RepeatableRead) { Lustra::SQL.select("1").execute }
    end

    it "rolls back queries on a named connection" do
      Lustra::SQL.execute("secondary", "DELETE FROM models_post_stats")

      begin
        Lustra::SQL.transaction("secondary") do
          Lustra::SQL.execute("secondary", "INSERT INTO models_post_stats (post_id) VALUES (1)")
          Lustra::SQL.rollback
        end

        count = Lustra::SQL::ConnectionPool.with_connection("secondary") do |connection|
          connection.query_one("SELECT COUNT(*) FROM models_post_stats", as: Int64)
        end
        count.should eq(0)
      ensure
        Lustra::SQL.execute("secondary", "DELETE FROM models_post_stats")
      end
    end

    it "commits queries on a named connection" do
      Lustra::SQL.execute("secondary", "DELETE FROM models_post_stats")

      begin
        Lustra::SQL.transaction("secondary") do
          Lustra::SQL.execute("secondary", "INSERT INTO models_post_stats (post_id) VALUES (1)")
        end

        count = Lustra::SQL::ConnectionPool.with_connection("secondary") do |connection|
          connection.query_one("SELECT COUNT(*) FROM models_post_stats", as: Int64)
        end
        count.should eq(1)
      ensure
        Lustra::SQL.execute("secondary", "DELETE FROM models_post_stats")
      end
    end

    it "uses a named connection for savepoints" do
      Lustra::SQL.execute("secondary", "DELETE FROM models_post_stats")

      begin
        Lustra::SQL.transaction("secondary") do
          Lustra::SQL.execute("secondary", "INSERT INTO models_post_stats (post_id) VALUES (1)")

          Lustra::SQL.with_savepoint(connection_name: "secondary") do
            Lustra::SQL.execute("secondary", "INSERT INTO models_post_stats (post_id) VALUES (2)")
            Lustra::SQL.rollback
          end
        end

        post_ids = Lustra::SQL::ConnectionPool.with_connection("secondary") do |connection|
          connection.query_all("SELECT post_id FROM models_post_stats ORDER BY post_id", as: Int32)
        end
        post_ids.should eq([1])
      ensure
        Lustra::SQL.execute("secondary", "DELETE FROM models_post_stats")
      end
    end

    it "rolls back nested transactions on a named connection" do
      Lustra::SQL.execute("secondary", "DELETE FROM models_post_stats")

      begin
        Lustra::SQL.transaction("secondary") do
          Lustra::SQL.execute("secondary", "INSERT INTO models_post_stats (post_id) VALUES (1)")

          Lustra::SQL.transaction("secondary") do
            Lustra::SQL.execute("secondary", "INSERT INTO models_post_stats (post_id) VALUES (2)")
            Lustra::SQL.rollback_transaction
          end
        end

        count = Lustra::SQL::ConnectionPool.with_connection("secondary") do |connection|
          connection.query_one("SELECT COUNT(*) FROM models_post_stats", as: Int64)
        end
        count.should eq(0)
      ensure
        Lustra::SQL.execute("secondary", "DELETE FROM models_post_stats")
      end
    end
  end

  describe "Lustra::SQL::Transaction#after_commit" do
    {"default", "secondary"}.each do |connection_name|
      it "discards rolled-back savepoint callbacks on #{connection_name}" do
        called = [] of String

        Lustra::SQL.transaction(connection_name) do
          Lustra::SQL.after_commit(connection_name) { called << "before" }

          Lustra::SQL.with_savepoint(connection_name: connection_name) do
            Lustra::SQL.after_commit(connection_name) { called << "rolled back" }
            Lustra::SQL.rollback
          end

          Lustra::SQL.after_commit(connection_name) { called << "after" }
          called.should be_empty
        end

        called.should eq(["before", "after"])
      end
    end

    it "discards released inner savepoint callbacks when their enclosing savepoint rolls back" do
      called = [] of String

      Lustra::SQL.transaction do
        Lustra::SQL.after_commit { called << "committed" }

        Lustra::SQL.with_savepoint do
          Lustra::SQL.after_commit { called << "outer savepoint" }
          Lustra::SQL.with_savepoint do
            Lustra::SQL.after_commit { called << "inner savepoint" }
          end
          Lustra::SQL.rollback
        end
      end

      called.should eq(["committed"])
    end

    it "runs released savepoint callbacks once and only after the outer commit" do
      called = [] of String

      Lustra::SQL.transaction do
        Lustra::SQL.after_commit { called << "outer" }
        Lustra::SQL.with_savepoint do
          Lustra::SQL.after_commit { called << "savepoint" }
        end
        called.should be_empty
      end

      called.should eq(["outer", "savepoint"])
      Lustra::SQL.transaction { }
      called.should eq(["outer", "savepoint"])
    end

    it "discards callbacks when an explicitly named savepoint rolls back" do
      called = [] of String

      Lustra::SQL.transaction do
        Lustra::SQL.after_commit { called << "outer" }
        Lustra::SQL.with_savepoint(sp_name: :callback_scope) do
          Lustra::SQL.after_commit { called << "savepoint" }
          Lustra::SQL.rollback
        end
      end

      called.should eq(["outer"])
    end

    it "executes the callback code when transaction is commited" do
      is_called = false

      Lustra::SQL.transaction do
        Lustra::SQL.after_commit { is_called = true }
        is_called.should be_false
      end

      is_called.should be_true
    end

    it "does not execute the callback code when transaction is rollback" do
      is_called = false

      Lustra::SQL.transaction do
        Lustra::SQL.after_commit do
          is_called = true
        end

        is_called.should be_false
        Lustra::SQL.rollback
      end

      channel = Channel(Nil).new

      5.times do
        # Ensure the list is lustra after this block
        # Using all the connections
        spawn do
          Lustra::SQL.transaction do
            channel.send(nil)
          end

          channel.send(nil)
        end
      end

      10.times { channel.receive } # Wait for all the fibers to finish.

      is_called.should be_false
    end

    it "doesn't call twice the callback" do
      is_called = 0

      Lustra::SQL.transaction do
        Lustra::SQL.after_commit { is_called += 1 }
        is_called.should eq(0)
      end

      is_called.should eq(1)
      Lustra::SQL.transaction { is_called.should eq(1) }
      is_called.should eq(1)
    end

    # Because after_commit is related to a specific transaction, it should raise
    # and error if we're not currently in transaction.
    it "raises an error if not yet in transaction" do
      expect_raises(Lustra::SQL::Error, /in transaction/) do
        Lustra::SQL.after_commit { puts "Do something" }
      end
    end

    it "is related to the current commit only" do
      # This test is a bit tricky to make it work
      # because the fiber scheduler is changing context on call to the database
      # (which are IO calls, so it makes sense).
      # To prevent this, we need to force waiting each fiber by using a channel
      channel = Channel(Nil).new
      called = "nope"

      Lustra::SQL.transaction do
        Lustra::SQL.after_commit { called = "last" }

        spawn do
          Lustra::SQL.transaction do
            Lustra::SQL.after_commit { called = "first" }
            channel.receive # Wait for the message to commit.
          end
          channel.send nil # We have now committed.
        end

        called.should eq("nope")  # No call yet.
        channel.send nil          # Call the commit of the other transaction
        channel.receive           # Wait for the other transaction to commit
        called.should eq("first") # Now we committed the first transaction.
      end                         # Finish second transaction

      called.should eq("last")
    end
  end
end
