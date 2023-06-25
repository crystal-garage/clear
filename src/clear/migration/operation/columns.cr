module Clear::Migration
  class AddColumn < Operation
    # ALTER TABLE {TABLENAME}
    # ADD {COLUMNNAME} {TYPE} {NULL|NOT NULL}
    # CONSTRAINT {CONSTRAINT_NAME} DEFAULT {DEFAULT_VALUE}
    # WITH VALUES

    @table : String
    @column : String
    @datatype : String

    @constraint : String?
    @default : String?
    @nullable : Bool

    @with_values : Bool

    def initialize(@table, @column, datatype, @nullable = false, @constraint = nil, @default = nil, @with_values = false)
      @datatype = Clear::Migration::Helper.datatype(datatype.to_s)
    end

    def up : Array(String)
      constraint = @constraint
      default = @default
      with_values = @with_values

      [[
        "ALTER TABLE", @table, "ADD", @column, @datatype, @nullable ? "NULL" : "NOT NULL",
        constraint ? "CONSTRAINT #{constraint}" : nil, default ? "DEFAULT #{default}" : nil,
        with_values ? "WITH VALUES" : nil,
      ].compact.join(" ")]
    end

    def down : Array(String)
      ["ALTER TABLE #{@table} DROP #{@column}"]
    end
  end

  class RemoveColumn < Operation
    @table : String
    @column : String
    @datatype : String

    def initialize(@table, @column, datatype)
      @datatype = Clear::Migration::Helper.datatype(datatype)
    end

    def up : Array(String)
      ["ALTER TABLE #{@table} DROP #{@column}"]
    end

    def down : Array(String)
      ["ALTER TABLE #{@table} ADD #{@column} #{@datatype}"]
    end
  end

  class RenameColumn < Operation
    @table : String
    @old_column_name : String
    @new_column_name : String

    def initialize(@table, @old_column_name, @new_column_name)
    end

    def up : Array(String)
      ["ALTER TABLE #{@table} RENAME COLUMN #{@old_column_name} TO #{@new_column_name};"]
    end

    def down : Array(String)
      ["ALTER TABLE #{@table} RENAME COLUMN #{@new_column_name} TO #{@old_column_name};"]
    end
  end

  class ChangeColumnType < Operation
    @table : String
    @column_name: String
    @new_column_type : String
    @old_column_type : String

    def initialize(@table, @column_name, old_column_type, new_column_type)
      @old_column_type = Clear::Migration::Helper.datatype(old_column_type)
      @new_column_type = Clear::Migration::Helper.datatype(new_column_type)
    end

    def up : Array(String)
      ["ALTER TABLE #{@table} ALTER COLUMN #{@column_name} SET DATA TYPE #{@new_column_type};"]
    end

    def down : Array(String)
      ["ALTER TABLE #{@table} ALTER COLUMN #{@column_name} SET DATA TYPE #{@old_column_type};"]
    end
  end
end

module Clear::Migration::Helper
  # Add a column to a specific table
  def add_column(table, column, datatype, nullable = false, constraint = nil, default = nil, with_values = false)
    self.add_operation(Clear::Migration::AddColumn.new(table, column, datatype,
      nullable, constraint, default, with_values))
  end

  def drop_column(table, column, type)
    self.add_operation(Clear::Migration::RemoveColumn.new(table, column, type))
  end

  def rename_column(table, from, to)
    self.add_operation(Clear::Migration::RenameColumn.new(table, from, to))
  end

  def change_column_type(table, column, from, to)
    self.add_operation(Clear::Migration::ChangeColumnType.new(table, column, from, to))
  end
end
