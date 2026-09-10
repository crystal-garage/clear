require "spec"

require "../spec_helper"

module InsertSpec
  extend self

  def insert_request
    Lustra::SQL::InsertQuery.new(:users)
  end

  def with_insert_connection_tables(&)
    Lustra::SQL.transaction do
      Lustra::SQL.transaction("secondary") do
        Lustra::SQL.execute("CREATE TEMP TABLE insert_connection_selection (value integer) ON COMMIT DROP")
        Lustra::SQL.execute("secondary", "CREATE TEMP TABLE insert_connection_selection (value integer) ON COMMIT DROP")
        yield
      end
    end
  end

  describe "Lustra::SQL" do
    describe "InsertQuery" do
      it "executes inserts on the query's selected connection" do
        with_insert_connection_tables do
          Lustra::SQL.insert_into(:insert_connection_selection, {value: 1})
            .use_connection("secondary")
            .execute

          Lustra::SQL.select.from(:insert_connection_selection).count.should eq(0)
          Lustra::SQL.select.from(:insert_connection_selection).use_connection("secondary").count.should eq(1)
        end
      end

      it "executes inserts with RETURNING on the query's selected connection" do
        with_insert_connection_tables do
          result = Lustra::SQL.insert_into(:insert_connection_selection, {value: 2})
            .use_connection("secondary")
            .returning("value")
            .execute

          result["value"].should eq(2)
          Lustra::SQL.select.from(:insert_connection_selection).count.should eq(0)
          Lustra::SQL.select.from(:insert_connection_selection).use_connection("secondary").count.should eq(1)
        end
      end

      it "counts inserted rows on the query's selected connection" do
        with_insert_connection_tables do
          affected = Lustra::SQL.insert_into(:insert_connection_selection, {value: 3})
            .use_connection("secondary")
            .execute_and_count

          affected.should eq(1)
          Lustra::SQL.select.from(:insert_connection_selection).count.should eq(0)
          Lustra::SQL.select.from(:insert_connection_selection).use_connection("secondary").count.should eq(1)
        end
      end

      it "honors explicit insert connection overrides" do
        with_insert_connection_tables do
          Lustra::SQL.insert_into(:insert_connection_selection, {value: 1})
            .use_connection("secondary")
            .execute("default")

          result = Lustra::SQL.insert_into(:insert_connection_selection, {value: 2})
            .use_connection("secondary")
            .returning("value")
            .execute("default")
          result["value"].should eq(2)

          affected = Lustra::SQL.insert_into(:insert_connection_selection, {value: 3})
            .use_connection("secondary")
            .execute_and_count("default")
          affected.should eq(1)

          Lustra::SQL.select.from(:insert_connection_selection).count.should eq(3)
          Lustra::SQL.select.from(:insert_connection_selection).use_connection("secondary").count.should eq(0)
        end
      end

      it "builds an insert with the zero-argument fluent API" do
        Lustra::SQL.insert
          .into(:users)
          .values({a: "c", b: 12})
          .to_sql
          .should eq %(INSERT INTO "users" ("a", "b") VALUES ('c', 12))
      end

      it "build an insert" do
        insert_request.values({a: "c", b: 12}).to_sql.should eq(
          "INSERT INTO \"users\" (\"a\", \"b\") VALUES ('c', 12)"
        )
      end

      it "aligns named tuple values with the first row's columns" do
        insert_request
          .values({first_name: "Ada", last_name: "Lovelace"})
          .values({last_name: "Hopper", first_name: "Grace"})
          .to_sql
          .should eq %(INSERT INTO "users" ("first_name", "last_name") VALUES ('Ada', 'Lovelace'),\n('Grace', 'Hopper'))
      end

      it "persists bulk hash rows by column name regardless of key order" do
        temporary do
          Lustra::SQL.execute("CREATE TEMP TABLE bulk_insert_alignment (first_name text, last_name text)")

          rows = [
            {"first_name" => "Ada", "last_name" => "Lovelace"} of Lustra::SQL::Symbolic => Lustra::SQL::InsertQuery::Inserable,
            {"last_name" => "Hopper", "first_name" => "Grace"} of Lustra::SQL::Symbolic => Lustra::SQL::InsertQuery::Inserable,
          ]

          Lustra::SQL.insert_into(:bulk_insert_alignment).values(rows).execute

          persisted = Lustra::SQL.select.from(:bulk_insert_alignment).order_by(:first_name).to_a
          persisted.map { |row| {row["first_name"], row["last_name"]} }.should eq([
            {"Ada", "Lovelace"},
            {"Grace", "Hopper"},
          ])
        end
      end

      it "rejects a bulk row with a missing column" do
        query = insert_request.values({first_name: "Ada", last_name: "Lovelace"})

        expect_raises(Lustra::SQL::QueryBuildingError) do
          query.values({first_name: "Grace"}).to_sql
        end
      end

      it "rejects a bulk row with an extra column" do
        query = insert_request.values({first_name: "Ada", last_name: "Lovelace"})

        expect_raises(Lustra::SQL::QueryBuildingError) do
          query.values({first_name: "Grace", last_name: "Hopper", nickname: "Amazing Grace"}).to_sql
        end
      end

      it "rejects a bulk row with different columns of the same count" do
        query = insert_request.values({first_name: "Ada", last_name: "Lovelace"})

        expect_raises(Lustra::SQL::QueryBuildingError) do
          query.values({first_name: "Grace", nickname: "Amazing Grace"}).to_sql
        end
      end

      it "build an insert from sql" do
        insert_request.values(
          Lustra::SQL.select.from(:old_users)
            .where { old_users.id > 100 }
        ).to_sql.should eq(
          "INSERT INTO \"users\" (SELECT * FROM \"old_users\" WHERE (\"old_users\".\"id\" > 100))"
        )
      end

      it "insert with ON CONFLICT" do
        insert_request.values({a: "c", b: 12}).on_conflict("(a)").do_nothing
          .to_sql.should eq(
          "INSERT INTO \"users\" (\"a\", \"b\") VALUES ('c', 12) ON CONFLICT (a) DO NOTHING"
        )

        req = insert_request.values({a: "c", b: 12}).on_conflict("(b)").do_update do |upd|
          upd.set(a: 1).where { b == 2 }
        end

        req.to_sql.should eq(
          %(INSERT INTO "users" ("a", "b") VALUES ('c', 12) ON CONFLICT (b) DO UPDATE SET "a" = 1 WHERE ("b" = 2))
        )

        req = insert_request.values({a: "c", b: 12}).on_conflict { age < 18 }.do_update do |upd|
          upd.set(a: 1).where { b == 2 }
        end

        req.to_sql.should eq(
          %(INSERT INTO "users" ("a", "b") VALUES ('c', 12) ON CONFLICT WHERE ("age" < 18) DO UPDATE SET "a" = 1 WHERE ("b" = 2))
        )
      end

      it "build an empty insert?" do
        insert_request.to_sql.should eq(
          "INSERT INTO \"users\" DEFAULT VALUES"
        )
      end

      it "insert unsafe values" do
        insert_request.values({created_at: Lustra::Expression.unsafe("NOW()")})
          .to_sql
          .should eq "INSERT INTO \"users\" (\"created_at\") VALUES (NOW())"
      end
    end
  end
end
