require "../spec_helper"
require "./12345_migration_by_file"

module MigrationSpec
  extend self

  class Migration1
    include Clear::Migration

    def change(dir)
      create_table(:test) do |t|
        t.column :first_name, "string", index: true
        t.column :last_name, "string", unique: true

        t.column :tags, "string", array: true, index: "gin"

        t.index "lower(first_name || ' ' || last_name)", using: :btree

        t.timestamps
      end
    end
  end

  class Migration2
    include Clear::Migration

    def change(dir)
      add_column "test", "middle_name", "text"
      create_index "test", "middle_name DESC"
    end
  end

  temporary do
    describe "Migration" do
      it "can discover UID from class name" do
        Migration1.new.uid.should eq 1
      end

      it "can discover UID from file name" do
        MigrationByFile.new.uid.should eq 12345
      end

      it "can apply migration" do
        temporary do
          Clear::Migration::Manager.instance.reinit!
          Migration1.new.apply(Clear::Migration::Direction::UP)

          Clear::Reflection::Table.public.where { table_name == "test" }.empty?.should eq false

          table = Clear::Reflection::Table.public.find! { table_name == "test" }
          columns = table.columns

          columns.dup.where { column_name == "first_name" }.empty?.should eq false
          columns.dup.where { column_name == "last_name" }.empty?.should eq false

          table.indexes.size.should eq 6

          Migration2.new.apply(Clear::Migration::Direction::UP)
          columns = table.columns
          columns.dup.where { column_name == "middle_name" }.empty?.should eq false
          table.indexes.size.should eq 7

          # Revert the last migration
          Migration2.new.apply(Clear::Migration::Direction::DOWN)
          columns = table.columns
          columns.dup.where { column_name == "middle_name" }.empty?.should eq true
          table.indexes.size.should eq 6

          # Revert the table migration
          Migration1.new.apply(Clear::Migration::Direction::DOWN)
          Clear::Reflection::Table.public.where { table_name == "test" }.empty?.should eq true
        end
      end
    end
  end

  describe "Migration" do
    it "can run migrations apply_all multiple times" do
      temporary do
        Clear::Migration::Manager.instance.reinit!
        # Ensure that multiple migration apply_all's can run without issue
        Clear::Migration::Manager.instance.apply_all
        Clear::Migration::Manager.instance.apply_all
      end
    end
  end
end
