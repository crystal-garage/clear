require "../../spec_helper"

# Having specs are essentially the same specs as the WHERE clause.
# This is because the HAVING block behaves essentially like the WHERE block.
#
# Therefore, the SQL tested in this test suite doesn't make sense.
module HavingSpec
  def self.complex_query
    Lustra::SQL.select.from(:users)
      .join(:role_users) { var("role_users", "user_id") == users.id }
      .join(:roles) { var("role_users", "role_id") == var("roles", "id") }
      .having({role: ["admin", "superadmin"]})
      .order_by({priority: :desc, name: :asc})
      .limit(50)
      .offset(50)
  end

  describe Lustra::SQL::Query::Having do
    it "accepts simple string as parameter" do
      r = Lustra::SQL.select.from(:users).having("a = b")
      r.to_sql.should eq %(SELECT * FROM "users" HAVING a = b)
    end

    it "transforms Nil to NULL" do
      q = Lustra::SQL.select.from(:users).having({user_id: nil})
      q.to_sql.should eq %(SELECT * FROM "users" HAVING ("user_id" IS NULL))
    end

    it "uses IN operator if an array is found" do
      q = Lustra::SQL.select.from(:users).having({user_id: [1, 2, 3, 4, "hello"]})
      q.to_sql.should eq %(SELECT * FROM "users" HAVING "user_id" IN (1, 2, 3, 4, 'hello'))
    end

    it "accepts ranges as tuple value and transform them" do
      Lustra::SQL.select.from(:users).having({x: 1..4}).to_sql
        .should eq %(SELECT * FROM "users" HAVING ("x" >= 1 AND "x" <= 4))
      Lustra::SQL.select.from(:users).having({x: 1...4}).to_sql
        .should eq %(SELECT * FROM "users" HAVING ("x" >= 1 AND "x" < 4))
      Lustra::SQL.select.from(:users).having({x: 1..}).to_sql
        .should eq %(SELECT * FROM "users" HAVING ("x" >= 1))
      Lustra::SQL.select.from(:users).having({x: ..10}).to_sql
        .should eq %(SELECT * FROM "users" HAVING ("x" <= 10))
      Lustra::SQL.select.from(:users).having({x: ...10}).to_sql
        .should eq %(SELECT * FROM "users" HAVING ("x" < 10))
    end

    it "allows prepared query" do
      r = Lustra::SQL.select.from(:users).having("a LIKE ?", "hello")
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING a LIKE 'hello'"

      r = Lustra::SQL.select.from(:users).having("a LIKE ?", "hello")
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING a LIKE 'hello'"
    end

    it "manages ranges" do
      Lustra::SQL.select.from(:users).having({x: 1..4}).to_sql
        .should eq "SELECT * FROM \"users\" HAVING (\"x\" >= 1 AND \"x\" <= 4)"

      Lustra::SQL.select.from(:users).having({x: 1...4}).to_sql
        .should eq "SELECT * FROM \"users\" HAVING (\"x\" >= 1 AND \"x\" < 4)"
    end

    it "prepare query" do
      r = Lustra::SQL.select.from(:users).having("a LIKE ?", "hello")
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING a LIKE 'hello'"
    end

    it "raises exception with prepared query" do
      expect_raises Lustra::SQL::QueryBuildingError do
        Lustra::SQL.select.from(:users).having("a LIKE ? AND b = ?", "hello")
      end
    end

    it "prepare query with tuple" do
      r = Lustra::SQL.select.from(:users).having("a LIKE :hello AND b LIKE :world",
        hello: "h", world: "w")
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING a LIKE 'h' AND b LIKE 'w'"
    end

    it "raises exception if a tuple element is not found" do
      expect_raises Lustra::SQL::QueryBuildingError do
        Lustra::SQL.select.from(:users).having("a LIKE :halo AND b LIKE :world", hello: "h", world: "w")
      end

      expect_raises Lustra::SQL::QueryBuildingError do
        Lustra::SQL.select.from(:users).or_having("a LIKE :halo AND b LIKE :world", hello: "h", world: "w")
      end
    end

    it "prepare group by query" do
      Lustra::SQL.select.select("role").from(:users).group_by(:role).order_by(:role).to_sql.should eq \
        "SELECT role FROM \"users\" GROUP BY \"role\" ORDER BY \"role\" ASC"
    end

    it "use different comparison and arithmetic operators" do
      r = Lustra::SQL.select.from(:users).having { users.id > 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING (\"users\".\"id\" > 1)"
      r = Lustra::SQL.select.from(:users).having { users.id < 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING (\"users\".\"id\" < 1)"
      r = Lustra::SQL.select.from(:users).having { users.id >= 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING (\"users\".\"id\" >= 1)"
      r = Lustra::SQL.select.from(:users).having { users.id <= 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING (\"users\".\"id\" <= 1)"
      r = Lustra::SQL.select.from(:users).having { users.id * 2 == 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING ((\"users\".\"id\" * 2) = 1)"
      r = Lustra::SQL.select.from(:users).having { users.id / 2 == 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING ((\"users\".\"id\" / 2) = 1)"
      r = Lustra::SQL.select.from(:users).having { users.id + 2 == 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING ((\"users\".\"id\" + 2) = 1)"
      r = Lustra::SQL.select.from(:users).having { users.id - 2 == 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING ((\"users\".\"id\" - 2) = 1)"
      r = Lustra::SQL.select.from(:users).having { -users.id < -1000 }
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING (-\"users\".\"id\" < -1000)"
    end

    it "use expression engine equal" do
      r = Lustra::SQL.select.from(:users).having { users.id == var("test") }
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING (\"users\".\"id\" = \"test\")"
    end

    it "use expression engine not equals" do
      r = Lustra::SQL.select.from(:users).having { users.id != 1 }
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING (\"users\".\"id\" <> 1)"
    end

    it "use expression engine not null" do
      r = Lustra::SQL.select.from(:users).having { users.id != nil }
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING (\"users\".\"id\" IS NOT NULL)"
    end

    it "use expression engine null" do
      r = Lustra::SQL.select.from(:users).having { users.id == nil }
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING (\"users\".\"id\" IS NULL)"
    end

    it "use expression engine null?" do
      r = Lustra::SQL.select.from(:users).having { users.id.null? }
      r.to_sql.should eq "SELECT * FROM \"users\" HAVING (\"users\".\"id\" IS NULL)"
    end

    describe "HAVING Expression engine Nodes" do
      it "stack with `AND` operator" do
        now = Time.local
        r = Lustra::SQL.select.from(:users).having { users.id == nil }.having do
          var("users", "updated_at") >= now
        end
        r.to_sql.should eq "SELECT * FROM \"users\" HAVING (\"users\".\"id\" IS NULL) " +
                           "AND (\"users\".\"updated_at\" >= #{Lustra::Expression[now]})"
      end

      it "stack with `OR` operator" do
        now = Time.local
        r = Lustra::SQL.select.from(:users).having { users.id == nil }.or_having do
          var("users", "updated_at") >= now
        end
        r.to_sql.should eq "SELECT * FROM \"users\" HAVING ((\"users\".\"id\" IS NULL) " +
                           "OR (\"users\".\"updated_at\" >= #{Lustra::Expression[now]}))"
      end

      it "AND and OR" do
        r = Lustra::SQL.select.from(:users).having do
          ((raw("users.id") > 100) & (raw("users.visible") == true)) |
            (raw("users.role") == "superadmin")
        end

        r.to_sql.should eq "SELECT * FROM \"users\" HAVING (((users.id > 100) " +
                           "AND (users.visible = TRUE)) OR (users.role = 'superadmin'))"
      end

      it "Operators" do
      end

      it "Between" do
        Lustra::SQL.select.having { x.between?(1, 2) }
          .to_sql.should eq(%(SELECT * HAVING ("x" BETWEEN 1 AND 2)))

        Lustra::SQL.select.having { not(x.between?(1, 2)) }
          .to_sql.should eq(%(SELECT * HAVING NOT ("x" BETWEEN 1 AND 2)))
      end

      it "Between with Time values" do
        time_start = Time.utc(2025, 1, 1, 12, 0, 0)
        time_end = Time.utc(2025, 1, 1, 15, 0, 0)

        Lustra::SQL.select.from(:users).having { created_at.between?(time_start, time_end) }
          .to_sql.should eq("SELECT * FROM \"users\" HAVING (\"created_at\" BETWEEN " +
                            "#{Lustra::Expression[time_start]} AND #{Lustra::Expression[time_end]})")

        Lustra::SQL.select.from(:users).having { not(created_at.between?(time_start, time_end)) }
          .to_sql.should eq("SELECT * FROM \"users\" HAVING NOT (\"created_at\" BETWEEN " +
                            "#{Lustra::Expression[time_start]} AND #{Lustra::Expression[time_end]})")
      end

      it "after? and before?" do
        Lustra::SQL.select.having { users.created_at.after?(posts.created_at) }
          .to_sql.should eq(%(SELECT * HAVING ("users"."created_at" > "posts"."created_at")))

        Lustra::SQL.select.having { users.created_at.before?(posts.created_at) }
          .to_sql.should eq(%(SELECT * HAVING ("users"."created_at" < "posts"."created_at")))
      end

      it "Function" do
        Lustra::SQL.select.having { ops_transform(x, "string", raw("INTERVAL '2 seconds'")) }
          .to_sql.should eq(%(SELECT * HAVING ops_transform("x", 'string', INTERVAL '2 seconds')))
      end

      it "InArray" do
        Lustra::SQL.select.having { x.in?([1, 2, 3, 4]) }
          .to_sql.should eq(%(SELECT * HAVING "x" IN (1, 2, 3, 4)))

        Lustra::SQL.select.having { x.in?({1, 2, 3, 4}) }
          .to_sql.should eq(%(SELECT * HAVING "x" IN (1, 2, 3, 4)))
      end

      it "InRange" do
        # Simple number
        Lustra::SQL.select.from(:users).having { users.id.in?(1..3) }.to_sql
          .should eq "SELECT * FROM \"users\" HAVING (\"users\".\"id\" >= 1 AND \"users\".\"id\" <= 3)"

        # Date range.
        range = 2.day.ago..1.day.ago

        Lustra::SQL.select.from(:users).having { created_at.in?(range) }.to_sql
          .should eq "SELECT * FROM \"users\" HAVING " +
                     "(\"created_at\" >= #{Lustra::Expression[range.begin]} AND" +
                     " \"created_at\" <= #{Lustra::Expression[range.end]})"

        # Exclusive range
        Lustra::SQL.select.from(:users).having { users.id.in?(1...3) }.to_sql
          .should eq "SELECT * FROM \"users\" HAVING (\"users\".\"id\" >= 1" +
                     " AND \"users\".\"id\" < 3)"

        # Endless range
        Lustra::SQL.select.from(:users).having { users.id.in?(10..) }.to_sql
          .should eq "SELECT * FROM \"users\" HAVING (\"users\".\"id\" >= 10)"

        # Beginless range (inclusive)
        Lustra::SQL.select.from(:users).having { users.id.in?(..100) }.to_sql
          .should eq "SELECT * FROM \"users\" HAVING (\"users\".\"id\" <= 100)"

        # Beginless range (exclusive)
        Lustra::SQL.select.from(:users).having { users.id.in?(...100) }.to_sql
          .should eq "SELECT * FROM \"users\" HAVING (\"users\".\"id\" < 100)"

        # Full range (...) - matches all values
        Lustra::SQL.select.from(:users).having { users.id.in?(...) }.to_sql
          .should eq "SELECT * FROM \"users\" HAVING TRUE"
      end

      it "InSelect" do
        sub_query = Lustra::SQL.select("id").from("users")
        Lustra::SQL.select.having { x.in?(sub_query) }
          .to_sql.should eq(%(SELECT * HAVING "x" IN (SELECT id FROM users)))
      end

      it "Minus" do
        Lustra::SQL.select.having { -x > 2 }
          .to_sql.should eq(%(SELECT * HAVING (-"x" > 2)))
      end

      it "Not" do
        Lustra::SQL.select.having { not(raw("TRUE")) }
          .to_sql.should eq(%(SELECT * HAVING NOT TRUE))

        Lustra::SQL.select.having { ~(raw("TRUE")) }
          .to_sql.should eq(%(SELECT * HAVING NOT TRUE))
      end

      it "Null" do
        Lustra::SQL.select.having { x == nil }
          .to_sql.should eq(%(SELECT * HAVING ("x" IS NULL)))
        Lustra::SQL.select.having { x != nil }
          .to_sql.should eq(%(SELECT * HAVING ("x" IS NOT NULL)))
      end

      it "Raw" do
        Lustra::SQL.select.having { raw("Anything") }
          .to_sql.should eq(%(SELECT * HAVING Anything))

        Lustra::SQL.select.having { raw("x > ?", 1) }
          .to_sql.should eq(%(SELECT * HAVING x > 1))

        Lustra::SQL.select.having { raw("x > :num", num: 2) }
          .to_sql.should eq(%(SELECT * HAVING x > 2))
      end

      it "Variable" do
        Lustra::SQL.select.having { var("public", "users", "id") < 1000 }
          .to_sql.should eq(%(SELECT * HAVING ("public"."users"."id" < 1000)))
      end
    end
  end
end
