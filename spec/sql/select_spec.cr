require "spec"

require "../spec_helper"

module SelectSpec
  extend self

  def select_request
    Clear::SQL::SelectQuery.new
  end

  def one_request
    select_request
      .select("MAX(updated_at)")
      .from(:users)
  end

  def complex_query
    select_request.from(:users)
      .join(:role_users) { var("role_users", "user_id") == users.id }
      .join(:roles) { var("role_users", "role_id") == var("roles", "id") }
      .where({role: ["admin", "superadmin"]})
      .order_by({priority: :desc, name: :asc})
      .limit(50)
      .offset(50)
  end

  describe "Clear::SQL" do
    describe "SelectQuery" do
      it "can create a simple request" do
        r = select_request
        r.to_sql.should eq "SELECT *"
      end

      it "can duplicate itself" do
        cq_2 = complex_query.dup
        cq_2.to_sql.should eq complex_query.to_sql
      end

      it "can transfert to delete method" do
        r = select_request.select("*").from(:users).where { raw("users.id") > 1000 }
        r.to_delete.to_sql.should eq "DELETE FROM \"users\" WHERE (users.id > 1000)"
      end

      it "can transfert to update method" do
        r = select_request.select("*").from(:users).where { var("users", "id") > 1000 }
        r.to_update.set(x: 1).to_sql.should eq "UPDATE \"users\" SET \"x\" = 1 WHERE (\"users\".\"id\" > 1000)"
      end

      describe "the ORDER BY clause" do
        it "can add NULLS FIRST and NULLS LAST" do
          r = select_request.from("users").order_by("email", "ASC", "NULLS LAST")
          r.to_sql.should eq "SELECT * FROM users ORDER BY email ASC NULLS LAST"
        end
      end

      describe "the FROM clause" do
        it "can build simple from" do
          r = select_request.from(:users)
          r.to_sql.should eq "SELECT * FROM \"users\""
        end

        it "can build multiple from" do
          r = select_request.from(:users, :posts)
          r.to_sql.should eq "SELECT * FROM \"users\", \"posts\""
        end

        it "can build named from" do
          r = select_request.from({customers: "users"})
          r.to_sql.should eq "SELECT * FROM users AS customers"
        end

        it "raise works with subquery as from" do
          r = select_request.from({q: complex_query})
          r.to_sql.should eq "SELECT * FROM ( #{complex_query.to_sql} ) q"
        end

        it "can write from by string" do
          r = select_request.from("(SELECT * FROM users LIMIT 10) users")
          r.to_sql.should eq "SELECT * FROM (SELECT * FROM users LIMIT 10) users"
        end

        it "can stack" do
          r = select_request.from("x").from(:y)
          r.to_sql.should eq "SELECT * FROM x, \"y\""
        end

        it "can be cleared" do
          r = select_request.from("x").clear_from.from("y")
          r.to_sql.should eq "SELECT * FROM y"
        end

        it "raise error if from subquery is not named" do
          expect_raises Clear::SQL::QueryBuildingError do
            r = select_request.from(complex_query)
            r.to_sql
          end
        end
      end

      describe "cte" do
        it "can build request with CTE" do
          # Simple CTE
          cte = select_request.from(:users_info).where("x > 10")
          sql = select_request.from(:ui).with_cte("ui", cte).to_sql
          sql.should eq "WITH ui AS (SELECT * FROM \"users_info\" WHERE x > 10) SELECT * FROM \"ui\""

          # Complex CTE
          cte1 = select_request.from(:users_info).where { a == b }
          cte2 = select_request.from(:just_another_table).where { users_infos.x == just_another_table.w }
          sql = select_request.with_cte({ui: cte1, at: cte2}).from(:at).to_sql
          sql.should eq "WITH ui AS (SELECT * FROM \"users_info\" WHERE (\"a\" = \"b\"))," +
                        " at AS (SELECT * FROM \"just_another_table\" WHERE (" +
                        "\"users_infos\".\"x\" = \"just_another_table\".\"w\")) SELECT * FROM \"at\""
        end
      end
    end
  end
end
