module Clear::Migration
  class CreateEnum < Operation
    @name : String
    @values : Array(String)

    def initialize(@name, @values)
    end

    def up : Array(String)
      ["CREATE TYPE #{@name} AS ENUM (#{Clear::Expression[@values].join(", ")})"]
    end

    def down : Array(String)
      ["DROP TYPE #{@name}"]
    end
  end

  class DropEnum < Operation
    @name : String
    @values : Array(String)?

    def initialize(@name, @values)
    end

    def up : Array(String)
      ["DROP TYPE #{@name}"]
    end

    def down : Array(String)
      if values = @values
        ["CREATE TYPE #{@name} AS ENUM (#{Clear::Expression[values].join(", ")})"]
      else
        irreversible!
      end
    end
  end

  module Helper
    def create_enum(name, arr : Enumerable(T)) forall T
      add_operation(CreateEnum.new(name.to_s, arr.map(&.to_s)))
    end

    def drop_enum(name, arr : Enumerable(T)? = nil) forall T
      add_operation(DropEnum.new(name.to_s, arr.try &.map(&.to_s)))
    end

    def create_enum(name, e)
      add_operation(CreateEnum.new(name.to_s, e.authorized_values))
    end
  end
end
