require "../spec_helper"
require "../data/example_models"

module GeometricSpec
  describe "PostgreSQL Geometric Types Complete Test Suite" do
    it "creates and retrieves geometric records" do
      temporary do
        reinit_example_models

        # Test Point type
        point_location = Location.create!(
          name: "Point Location",
          coordinates: PG::Geo::Point.new(40.7128, -74.0060)
        )

        # Test Circle type
        circle_location = Location.create!(
          name: "Circle Location",
          coordinates: PG::Geo::Point.new(42.3601, -71.0589),
          coverage_area: PG::Geo::Circle.new(42.3601, -71.0589, 0.08)
        )

        # Test Polygon type
        polygon_location = Location.create!(
          name: "Polygon Location",
          coordinates: PG::Geo::Point.new(39.9526, -75.1652),
          service_boundary: PG::Geo::Polygon.new([
            PG::Geo::Point.new(39.9, -75.2),
            PG::Geo::Point.new(40.0, -75.2),
            PG::Geo::Point.new(40.0, -75.1),
            PG::Geo::Point.new(39.9, -75.1),
          ])
        )

        # Test Box type
        box_location = Location.create!(
          name: "Box Location",
          coordinates: PG::Geo::Point.new(34.0522, -118.2437),
          bounding_box: PG::Geo::Box.new(34.0, -118.3, 34.1, -118.2)
        )

        # Test retrieval and verification
        locations = Location.query.order_by(:name).to_a
        locations.size.should eq(4)

        # Verify Point
        point = locations.find { |l| l.name == "Point Location" }
        point.should_not be_nil
        point.not_nil!.coordinates.x.should be_close(40.7128, 0.001)
        point.not_nil!.coordinates.y.should be_close(-74.0060, 0.001)

        # Verify Circle
        circle = locations.find { |l| l.name == "Circle Location" }
        circle.should_not be_nil
        circle.not_nil!.coverage_area.should_not be_nil
        circle.not_nil!.coverage_area.not_nil!.radius.should be_close(0.08, 0.001)

        # Verify Polygon
        polygon = locations.find { |l| l.name == "Polygon Location" }
        polygon.should_not be_nil
        polygon.not_nil!.service_boundary.should_not be_nil
        polygon.not_nil!.service_boundary.not_nil!.points.size.should eq(4)

        # Verify Box
        box = locations.find { |l| l.name == "Box Location" }
        box.should_not be_nil
        box.not_nil!.bounding_box.should_not be_nil
        box_val = box.not_nil!.bounding_box.not_nil!
        box_val.x1.should be_close(34.0, 0.001)
        box_val.x2.should be_close(34.1, 0.001)
      end
    end

    it "validates geometric expression engine work correctly" do
      temporary do
        reinit_example_models

        Location.create!(
          name: "NYC Store",
          coordinates: PG::Geo::Point.new(40.7128, -74.0060),
          coverage_area: PG::Geo::Circle.new(40.7128, -74.0060, 0.1),
          service_boundary: PG::Geo::Polygon.new([
            PG::Geo::Point.new(40.7, -74.1),
            PG::Geo::Point.new(40.8, -74.1),
            PG::Geo::Point.new(40.8, -74.0),
            PG::Geo::Point.new(40.7, -74.0),
          ])
        )

        # Test variables
        target_point = PG::Geo::Point.new(40.713, -74.006)
        max_distance = 1000.0
        user_location = PG::Geo::Point.new(40.72, -74.01) # Inside NYC coverage area

        # Test: Individual geometric operations work
        distance_query = Location.query.where { coordinates.distance_from(target_point) <= max_distance }
        distance_query.to_sql.should contain("<-> point(40.713,-74.006)")
        distance_query.to_sql.should contain("<= 1000.0")
        distance_query.size.should eq(1)

        # Test: Containment operations work
        containment_query = Location.query.where { coverage_area.contains?(user_location) }
        containment_query.to_sql.should contain("@> point(40.72,-74.01)")
        containment_query.size.should eq(1)

        # Test: Complex combined query
        # Note: Using points that are actually within the geometric shapes
        point_in_polygon = PG::Geo::Point.new(40.75, -74.05) # Inside the service boundary

        combined_query = Location.query.where do
          (coordinates.distance_from(target_point) <= max_distance) &
            (coverage_area.contains?(user_location)) &
            (service_boundary.contains?(point_in_polygon))
        end

        # Verify the SQL is correctly generated with proper operators and PostgreSQL format
        sql = combined_query.to_sql
        sql.should contain("<-> point(40.713,-74.006)")
        sql.should contain("@> point(40.72,-74.01)")
        sql.should contain("@> point(40.75,-74.05)")
        sql.should contain("AND") # Verify the query executes successfully
        combined_query.size.should eq(1)
        combined_query.first!.name.should eq("NYC Store")
      end
    end

    it "tests geometric operations with Location model" do
      temporary do
        reinit_example_models

        # Create test locations with different geometric data
        downtown = Location.create!({
          name:          "Downtown",
          coordinates:   PG::Geo::Point.new(-74.0060, 40.7128),                  # NYC coordinates
          coverage_area: PG::Geo::Circle.new(-74.0060, 40.7128, 1000.0),         # 1000 unit radius
          bounding_box:  PG::Geo::Box.new(-74.0160, 40.7028, -73.9960, 40.7228), # Bounding box around downtown
        })

        uptown = Location.create!({
          name:          "Uptown",
          coordinates:   PG::Geo::Point.new(-73.9857, 40.7589),         # Uptown NYC
          coverage_area: PG::Geo::Circle.new(-73.9857, 40.7589, 800.0), # 800 unit radius
        })

        brooklyn = Location.create!({
          name:          "Brooklyn",
          coordinates:   PG::Geo::Point.new(-73.9442, 40.6782),          # Brooklyn
          coverage_area: PG::Geo::Circle.new(-73.9442, 40.6782, 1200.0), # 1200 unit radius
        })

        # Test distance queries
        target_point = PG::Geo::Point.new(-74.0000, 40.7100) # Close to downtown

        closest_locations = Location.query
          .order_by("coordinates <-> point(#{target_point.x},#{target_point.y})")
          .limit(2)

        closest_locations.size.should eq(2)
        closest_locations.first!.name.should eq("Downtown") # Should be closest

        # Test distance_from in where clause
        nearby_locations = Location.query
          .where { coordinates.distance_from(target_point) <= 0.02 } # Small distance for coordinate system

        nearby_locations.any? { |loc| loc.name == "Downtown" }.should be_true

        # Test within_distance? method
        within_range = Location.query
          .where { coordinates.within_distance?(target_point, 0.02) }

        within_range.size.should eq(nearby_locations.size)

        # Test containment with coverage areas
        test_point = PG::Geo::Point.new(-74.0050, 40.7120) # Point near downtown

        covering_locations = Location.query
          .where { coverage_area.contains?(test_point) }

        # Should find locations whose coverage area contains the test point
        covering_locations.present?.should be_true

        # Test bounding box containment
        point_in_box = PG::Geo::Point.new(-74.0100, 40.7100) # Point that should be in downtown bounding box

        locations_containing_point = Location.query
          .where { bounding_box.contains?(point_in_box) }

        locations_containing_point.any? { |loc| loc.name == "Downtown" }.should be_true

        # Test overlap operations
        test_circle = PG::Geo::Circle.new(-74.0070, 40.7130, 500.0) # Circle near downtown

        overlapping_locations = Location.query
          .where { coverage_area.overlaps?(test_circle) }

        overlapping_locations.present?.should be_true

        # Test positioning operations
        reference_point = PG::Geo::Point.new(-74.0000, 40.7200)

        # Find locations to the left (west) of reference point
        west_locations = Location.query
          .where { coordinates.left_of?(reference_point) }

        # Find locations below (south) of reference point
        south_locations = Location.query
          .where { coordinates.below?(reference_point) }

        # Find the location with matching coordinates
        same_location = Location.query
          .where { coordinates.same_as?(PG::Geo::Point.new(-74.0060, 40.7128)) }

        same_location.size.should eq(1)
        same_location.first!.name.should eq("Downtown")

        # Test combined geometric operations
        center_point = PG::Geo::Point.new(-74.0000, 40.7100)
        max_distance = 0.05

        complex_query_results = Location.query.where do
          (coordinates.distance_from(center_point) <= max_distance) &
            (coverage_area.contains?(center_point))
        end.to_a

        # Should work without errors
        complex_query_results.is_a?(Array(Location)).should be_true
      end
    end

    it "tests geometric operations with Store model and custom scopes" do
      temporary do
        reinit_example_models

        # Create test stores with delivery areas
        manhattan_store = Store.create!({
          name:          "Manhattan Store",
          address:       "123 Broadway, NYC",
          location:      PG::Geo::Point.new(-74.0060, 40.7128),
          delivery_area: PG::Geo::Polygon.new([
            PG::Geo::Point.new(-74.0200, 40.7000),
            PG::Geo::Point.new(-73.9900, 40.7000),
            PG::Geo::Point.new(-73.9900, 40.7300),
            PG::Geo::Point.new(-74.0200, 40.7300),
          ]),
          pickup_radius: PG::Geo::Circle.new(-74.0060, 40.7128, 500.0),
        })

        brooklyn_store = Store.create!({
          name:          "Brooklyn Store",
          address:       "456 Atlantic Ave, Brooklyn",
          location:      PG::Geo::Point.new(-73.9442, 40.6782),
          delivery_area: PG::Geo::Polygon.new([
            PG::Geo::Point.new(-73.9600, 40.6600),
            PG::Geo::Point.new(-73.9300, 40.6600),
            PG::Geo::Point.new(-73.9300, 40.6900),
            PG::Geo::Point.new(-73.9600, 40.6900),
          ]),
          pickup_radius: PG::Geo::Circle.new(-73.9442, 40.6782, 300.0),
        })

        # Test custom scope: can_deliver_to
        customer_location = PG::Geo::Point.new(-74.0100, 40.7100) # Manhattan customer

        delivery_stores = Store.can_deliver_to(customer_location).to_a
        delivery_stores.any? { |store| store.name == "Manhattan Store" }.should be_true

        # Test custom scope: pickup_available
        pickup_stores = Store.pickup_available(customer_location).to_a
        pickup_stores.present?.should be_true

        # Test direct geometric queries on Store model
        nearby_stores = Store.query
          .where { location.within_distance?(customer_location, 0.02) }

        nearby_stores.empty?.should be_false

        # Test containment queries
        point_in_brooklyn = PG::Geo::Point.new(-73.9400, 40.6750)

        brooklyn_delivery_stores = Store.query
          .where { delivery_area.contains?(point_in_brooklyn) }

        brooklyn_delivery_stores.any? { |store| store.name == "Brooklyn Store" }.should be_true

        # Test ordering by distance
        ordered_stores = Store.query
          .order_by("location <-> point(#{customer_location.x},#{customer_location.y})")

        ordered_stores.size.should eq(2)
        # Manhattan store should be closer to Manhattan customer
        ordered_stores.first!.name.should eq("Manhattan Store")

        # Test overlap operations with pickup radius
        large_area = PG::Geo::Circle.new(-74.0000, 40.7000, 2000.0) # Large circle covering both stores

        stores_with_overlapping_pickup = Store.query
          .where { pickup_radius.overlaps?(large_area) }

        stores_with_overlapping_pickup.size.should eq(2) # Both stores should overlap with large area

        # Test intersection with compatible types - polygon && polygon (overlap)
        test_area = PG::Geo::Polygon.new([
          PG::Geo::Point.new(-74.0100, 40.7050),
          PG::Geo::Point.new(-73.9500, 40.7050),
          PG::Geo::Point.new(-73.9500, 40.7150),
          PG::Geo::Point.new(-74.0100, 40.7150),
        ]) # Area overlapping with Manhattan store delivery area

        overlapping_delivery_areas = Store.query
          .where { delivery_area.overlaps?(test_area) }

        overlapping_delivery_areas.any? { |store| store.name == "Manhattan Store" }.should be_true
      end
    end

    it "tests error handling with geometric operations" do
      temporary do
        reinit_example_models

        # Create location without optional geometric columns
        simple_location = Location.create!({
          name:        "Simple Location",
          coordinates: PG::Geo::Point.new(-74.0060, 40.7128), # coverage_area and bounding_box are nil
        })

        # Test queries with nil geometric columns should work
        test_point = PG::Geo::Point.new(-74.0050, 40.7120)

        # This should not crash even though coverage_area is nil for some records
        results = Location.query
          .where { coordinates.distance_from(test_point) <= 0.01 }

        results.any? { |loc| loc.name == "Simple Location" }.should be_true

        # Test that we can query for non-null geometric columns
        locations_with_coverage = Location.query
          .where("coverage_area IS NOT NULL")

        # Should not include our simple_location
        locations_with_coverage.any? { |loc| loc.name == "Simple Location" }.should be_false
      end
    end
  end
end
