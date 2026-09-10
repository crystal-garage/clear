module Lustra::SQL::Transaction
  # Represents the different transaction isolation levels,
  #   as described in https://www.postgresql.org/docs/9.5/transaction-iso.html
  #
  #   ReadUncommitted is intentionally omitted because it falls back to
  #   ReadCommitted in PostgreSQL.
  enum Level
    ReadCommitted
    RepeatableRead
    Serializable

    # :nodoc:
    def to_begin_operation
      case self
      when ReadCommitted
        "BEGIN TRANSACTION ISOLATION LEVEL READ COMMITTED"
      when RepeatableRead
        "BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ"
      else # Serializable is the default
        "BEGIN TRANSACTION ISOLATION LEVEL SERIALIZABLE"
      end
    end
  end

  @@savepoint_uid : UInt64 = 0_u64
  @@commit_callbacks = Hash(DB::Connection, Array(DB::Connection ->)).new { [] of DB::Connection -> }

  # Check whether the current fiber/connection pair is in a transaction block.
  def in_transaction?(connection : String = "default")
    Lustra::SQL::ConnectionPool.with_connection(connection, &._in_transaction?)
  end

  # Enter a new transaction block for the current connection/fiber pair.
  # Defaults to Serializable, independently of the PostgreSQL session default.
  # Pass Level::ReadCommitted explicitly when weaker isolation is intended.
  # Nested calls reuse the outer transaction and its isolation level.
  #
  # Example:
  #
  # ```
  # Lustra::SQL.transaction do
  #   # do something
  #   Lustra::SQL.transaction do # Technically, this block does nothing, since we already are in a transaction
  #     rollback                 # < Roll back the outermost `transaction` block.
  #   end
  # end
  # ```
  #
  # See #with_savepoint for a stackable version using savepoints.
  #
  def transaction(connection : String = "default", level : Level = Level::Serializable, &)
    Lustra::SQL::ConnectionPool.with_connection(connection) do |cnx|
      has_rollback = false

      if cnx._in_transaction?
        return yield(cnx) # In case we already are in transaction, we just ignore
      else
        cnx._in_transaction = true
        execute(connection, level.to_begin_operation)
        begin
          return yield(cnx)
        rescue e
          has_rollback = true
          is_rollback_error = e.is_a?(RollbackError) || e.is_a?(CancelTransactionError)
          execute(connection, "ROLLBACK --" + (is_rollback_error ? "normal" : "program error")) rescue nil
          raise e unless is_rollback_error
        ensure
          cnx._in_transaction = false

          callbacks = @@commit_callbacks.delete(cnx)

          unless has_rollback
            execute(connection, "COMMIT")

            # Remove the list from the global hash and execute after commit.
            # This prevents the proc from being called twice if a new Lustra
            # transaction is opened inside the `after_commit` block.
            callbacks.try &.each &.call(cnx)
          end
        end
      end
    end
  end

  # Register a callback function that fires once when SQL `COMMIT` is called.
  #
  # This can be used to send email or perform other tasks when you want to be
  # sure the data is committed in the database.
  #
  # ```
  # transaction do
  #   @user = User.find(1)
  #   @user.subscribe!
  #   Lustra::SQL.after_commit { Email.deliver(ConfirmationMail.new(@user)) }
  # end
  # ```
  #
  # If the transaction fails and rolls back, the callback won't be called.
  #
  def after_commit(connection : String = "default", &block : DB::Connection -> Nil)
    Lustra::SQL::ConnectionPool.with_connection(connection) do |cnx|
      if cnx._in_transaction?
        @@commit_callbacks[cnx] <<= block
      else
        raise Lustra::SQL::Error.new("you need to be in transaction to add after_commit callback")
      end
    end
  end

  # Create a stackable transaction using savepoints.
  #
  # Example:
  #
  # ```
  # Lustra::SQL.with_savepoint do
  #   # do something
  #   Lustra::SQL.with_savepoint do
  #     rollback # < Rollback only the last `with_savepoint` block
  #   end
  # end
  # ```
  def with_savepoint(sp_name : Symbolic? = nil, connection_name : String = "default", &)
    transaction(connection_name) do |cnx|
      sp_name ||= "sp_#{@@savepoint_uid += 1}"
      execute(connection_name, "SAVEPOINT #{sp_name}")
      yield
      execute(connection_name, "RELEASE SAVEPOINT #{sp_name}") if cnx._in_transaction?
    rescue e : RollbackError
      if cnx._in_transaction?
        execute(connection_name, "ROLLBACK TO SAVEPOINT #{sp_name}")
        raise e if e.savepoint_id.try &.!=(sp_name)
      end
    end
  end

  # Rollback a transaction or return to the previous savepoint in case of a
  # with_savepoint block.
  # The params `to` offer
  def rollback(to = nil)
    raise RollbackError.new(to)
  end

  # Rollback the transaction. In case the call is made inside a savepoint block
  # rollback everything.
  def rollback_transaction
    raise CancelTransactionError.new
  end
end
