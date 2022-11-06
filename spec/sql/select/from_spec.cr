require "../../spec_helper"

module FromSpec
  extend self

  def complex_query
    Clear::SQL.select.from(:users)
      .join(:role_users) { var("role_users", "user_id") == users.id }
      .join(:roles) { var("role_users", "role_id") == var("roles", "id") }
      .where({role: ["admin", "superadmin"]})
      .order_by({priority: :desc, name: :asc})
      .limit(50)
      .offset(50)
  end

  describe Clear::SQL::Query::From do
    it "can build simple from" do
      r = Clear::SQL.select.from(:users)
      r.to_sql.should eq "SELECT * FROM \"users\""
    end

    it "can build multiple from" do
      r = Clear::SQL.select.from(:users, :posts)
      r.to_sql.should eq "SELECT * FROM \"users\", \"posts\""
    end

    it "can build named from" do
      r = Clear::SQL.select.from({customers: "users"})
      r.to_sql.should eq "SELECT * FROM users AS customers"
    end

    it "raise works with subquery as from" do
      r = Clear::SQL.select.from({q: complex_query})
      r.to_sql.should eq "SELECT * FROM ( #{complex_query.to_sql} ) q"
    end

    it "can write from by string" do
      r = Clear::SQL.select.from("(SELECT * FROM users LIMIT 10) users")
      r.to_sql.should eq "SELECT * FROM (SELECT * FROM users LIMIT 10) users"
    end

    it "can stack" do
      r = Clear::SQL.select.from("x").from(:y)
      r.to_sql.should eq "SELECT * FROM x, \"y\""
    end

    it "can be cleared" do
      r = Clear::SQL.select.from("x").clear_from.from("y")
      r.to_sql.should eq "SELECT * FROM y"
    end

    it "raise error if from subquery is not named" do
      expect_raises Clear::SQL::QueryBuildingError do
        r = Clear::SQL.select.from(complex_query)
        r.to_sql
      end
    end
  end
end
