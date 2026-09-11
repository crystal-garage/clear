require "spec"

require "../spec_helper"

module SelectSpec
  extend self

  def complex_query
    Lustra::SQL.select.from(:users)
      .join(:role_users) { var("role_users", "user_id") == users.id }
      .join(:roles) { var("role_users", "role_id") == var("roles", "id") }
      .where({role: ["admin", "superadmin"]})
      .order_by({priority: :desc, name: :asc})
      .limit(50)
      .offset(50)
  end

  describe "Lustra::SQL" do
    describe "SelectQuery" do
      it "create a simple request" do
        r = Lustra::SQL.select
        r.to_sql.should eq "SELECT *"
      end

      it "duplicate itself" do
        cq_2 = complex_query.dup
        cq_2.to_sql.should eq complex_query.to_sql
      end

      it "preserves the original query's hooks after executing a duplicate" do
        calls = 0
        original = Lustra::SQL.select("1").before_query { calls += 1 }
        copy = original.dup

        copy.to_a
        calls.should eq(1)
        original.to_a
        calls.should eq(2)
      end

      it "does not add a duplicate's hooks to the original query" do
        calls = 0
        original = Lustra::SQL.select("1")
        copy = original.dup.before_query { calls += 1 }

        original.to_a
        calls.should eq(0)
        copy.to_a
        calls.should eq(1)
      end

      it "transfert to delete method" do
        r = Lustra::SQL.select("*").from(:users).where { raw("users.id") > 1000 }
        r.to_delete.to_sql.should eq "DELETE FROM \"users\" WHERE (users.id > 1000)"
      end

      it "adds a returning clause to a delete" do
        r = Lustra::SQL.select("*").from(:users).where { var("users", "id") > 1000 }

        r.to_delete
          .returning("id, email")
          .to_sql.should eq "DELETE FROM \"users\" WHERE (\"users\".\"id\" > 1000) RETURNING id, email"
      end

      it "transfert to update method" do
        r = Lustra::SQL.select("*").from(:users).where { var("users", "id") > 1000 }
        r.to_update.set(x: 1).to_sql.should eq "UPDATE \"users\" SET \"x\" = 1 WHERE (\"users\".\"id\" > 1000)"
      end

      it "adds a returning clause to an update" do
        r = Lustra::SQL.select("*").from(:users).where { var("users", "id") > 1000 }

        r.to_update
          .set(x: 1)
          .returning("id, email")
          .to_sql.should eq "UPDATE \"users\" SET \"x\" = 1 WHERE (\"users\".\"id\" > 1000) RETURNING id, email"
      end

      describe "cte" do
        it "build request with CTE" do
          # Simple CTE
          cte = Lustra::SQL.select.from(:users_info).where("x > 10")
          sql = Lustra::SQL.select.from(:ui).with_cte("ui", cte).to_sql
          sql.should eq "WITH ui AS (SELECT * FROM \"users_info\" WHERE x > 10) SELECT * FROM \"ui\""

          # Complex CTE
          cte1 = Lustra::SQL.select.from(:users_info).where { a == b }
          cte2 = Lustra::SQL.select.from(:just_another_table).where { users_infos.x == just_another_table.w }
          sql = Lustra::SQL.select.with_cte({ui: cte1, at: cte2}).from(:at).to_sql
          sql.should eq "WITH ui AS (SELECT * FROM \"users_info\" WHERE (\"a\" = \"b\"))," +
                        " at AS (SELECT * FROM \"just_another_table\" WHERE (" +
                        "\"users_infos\".\"x\" = \"just_another_table\".\"w\")) SELECT * FROM \"at\""
        end
      end
    end
  end
end
