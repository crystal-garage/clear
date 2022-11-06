require "../../spec_helper"

module SelectSpec
  extend self

  def one_request
    Clear::SQL
      .select("MAX(updated_at)")
      .from(:users)
  end

  describe Clear::SQL::Query::Select do
    it "can select wildcard *" do
      r = Clear::SQL.select("*")
      r.to_sql.should eq "SELECT *"
    end

    it "can select distinct" do
      r = Clear::SQL.select("*").distinct
      r.to_sql.should eq "SELECT DISTINCT *"

      r = Clear::SQL.select("a", "b", "c").distinct
      r.to_sql.should eq "SELECT DISTINCT a, b, c"

      r = Clear::SQL.select(:first_name, :last_name, :id).distinct
      r.to_sql.should eq "SELECT DISTINCT \"first_name\", \"last_name\", \"id\""
    end

    it "can select any string" do
      r = Clear::SQL.select("1")
      r.to_sql.should eq "SELECT 1"
    end

    it "can select using variables" do
      r = Clear::SQL.select("SUM(quantity) AS sum", "COUNT(*) AS count")
      # No escape with string, escape must be done manually
      r.to_sql.should eq "SELECT SUM(quantity) AS sum, COUNT(*) AS count"
    end

    it "can select using multiple strings" do
      r = Clear::SQL.select({uid: "user_id", some_cool_stuff: "column"})
      r.to_sql.should eq "SELECT user_id AS uid, column AS some_cool_stuff"
    end

    it "can reset the select" do
      r = Clear::SQL.select("1").clear_select.select("2")
      r.to_sql.should eq "SELECT 2"
    end

    it "can select a subquery" do
      r = Clear::SQL.select({max_updated_at: one_request})
      r.to_sql.should eq "SELECT ( #{one_request.to_sql} ) AS max_updated_at"
    end
  end
end
