require "../../spec_helper"

module OrderBySpec
  describe Clear::SQL::Query::OrderBy do
    it "can add NULLS FIRST and NULLS LAST" do
      r = Clear::SQL.select.from("users").order_by("email", "ASC", "NULLS LAST")
      r.to_sql.should eq "SELECT * FROM users ORDER BY email ASC NULLS LAST"
    end
  end
end
