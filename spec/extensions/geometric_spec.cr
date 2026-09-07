require "../spec_helper"

describe "Lustra Geometric Extensions" do
  describe "Expression Engine Geometric Operations" do
    it "should generate correct distance queries" do
      point = PG::Geo::Point.new(3.0, 4.0)

      # Test distance_from method
      expression = Lustra::Expression.where { coordinates.distance_from(point) }
      expression.resolve.should eq("(\"coordinates\" <-> point(3.0,4.0))")
    end

    it "should generate correct containment queries" do
      point = PG::Geo::Point.new(1.0, 1.0)

      # Test contains? method
      expression = Lustra::Expression.where { search_area.contains?(point) }
      expression.resolve.should eq("(\"search_area\" @> point(1.0,1.0))")

      # Test contained_by? method (reverse containment)
      polygon = PG::Geo::Polygon.new([PG::Geo::Point.new(0.0, 0.0), PG::Geo::Point.new(2.0, 0.0), PG::Geo::Point.new(2.0, 2.0), PG::Geo::Point.new(0.0, 2.0)])
      expression = Lustra::Expression.where { coordinates.contained_by?(polygon) }
      expression.resolve.should eq("(polygon'((0.0,0.0),(2.0,0.0),(2.0,2.0),(0.0,2.0))' @> \"coordinates\")")
    end

    it "should generate correct overlap queries" do
      circle = PG::Geo::Circle.new(3.0, 4.0, 3.0)

      # Test overlaps? method
      expression = Lustra::Expression.where { area.overlaps?(circle) }
      expression.resolve.should eq("(\"area\" && circle(point(3.0,4.0),3.0))")
    end

    it "should generate correct intersection queries" do
      line = PG::Geo::Line.new(1.0, -1.0, 0.0) # Line equation: x - y = 0

      # Test intersects? method
      expression = Lustra::Expression.where { path.intersects?(line) }
      expression.resolve.should eq("(\"path\" ?# line'{1.0,-1.0,0.0}')")
    end

    it "should generate correct positioning queries" do
      point = PG::Geo::Point.new(5.0, 0.0)

      # Test left_of? method
      expression = Lustra::Expression.where { coordinates.left_of?(point) }
      expression.resolve.should eq("(\"coordinates\" << point(5.0,0.0))")

      # Test right_of? method
      expression = Lustra::Expression.where { coordinates.right_of?(point) }
      expression.resolve.should eq("(\"coordinates\" >> point(5.0,0.0))")

      # Test above? method
      expression = Lustra::Expression.where { coordinates.above?(point) }
      expression.resolve.should eq("(\"coordinates\" |>> point(5.0,0.0))")

      # Test below? method
      expression = Lustra::Expression.where { coordinates.below?(point) }
      expression.resolve.should eq("(\"coordinates\" <<| point(5.0,0.0))")

      # Test same_as? method
      expression = Lustra::Expression.where { coordinates.same_as?(point) }
      expression.resolve.should eq("(\"coordinates\" ~= point(5.0,0.0))")
    end

    it "should combine distance with comparison operators" do
      point = PG::Geo::Point.new(0.0, 0.0)
      max_distance = 1000.0

      # Test within_distance? method
      expression = Lustra::Expression.where { coordinates.within_distance?(point, max_distance) }
      expression.resolve.should eq("((\"coordinates\" <-> point(0.0,0.0)) <= 1000.0)")
    end
  end
end
