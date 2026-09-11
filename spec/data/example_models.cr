Lustra.enum GenderType, "male", "female", "other" do
  def male?
    self == Male
  end

  def female?
    self == Female
  end

  def other?
    self == Other
  end
end

class User
  include Lustra::Model

  primary_key

  column first_name : String
  column last_name : String?
  column middle_name : String?, mass_assign: false

  column gender : GenderType?

  column active : Bool?
  column posts_count : Int32, presence: false

  column notification_preferences : JSON::Any, presence: false
  column last_comment_at : Time?

  has_many posts : Post, autosave: true
  has_many comments : Comment
  has_one info : UserInfo
  has_many categories : Category, through: Post

  has_many relationships : Relationship, foreign_key: "master_id"
  has_many dependencies : User, through: Relationship, foreign_key: "dependency_id", own_key: "master_id"
  has_many dependents : User, through: Relationship, foreign_key: "master_id", own_key: "dependency_id"

  timestamps

  # Random virtual method
  def full_name=(x)
    self.first_name, self.last_name = x.split(" ")
  end

  def full_name
    {self.first_name, self.last_name}.join(" ")
  end
end

class Employee
  include Lustra::Model

  primary_key

  column name : String

  has_many pictures : Picture, as: :imageable
end

class Product
  include Lustra::Model

  primary_key

  column name : String

  has_many pictures : Picture, as: :imageable
end

class Post
  include Lustra::Model

  primary_key

  column title : String

  column tags_list : Array(String), presence: false
  column flags : Array(Int64), presence: false, column_name: "flags_other_column_name"

  column content : String, presence: false

  column published : Bool, presence: false

  scope("published") { where published: true }

  def validate
    ensure_than(title, "title: is empty", &.size.>(0))
  end

  has_many post_tags : PostTag
  has_many tags : Tag, through: PostTag, autosave: true

  # belongs_to user : User, counter_cache: :posts_count
  belongs_to user : User, counter_cache: true

  belongs_to category : Category, foreign_key_type: Int32?
end

class PostWithTouch
  include Lustra::Model

  self.table = "posts_with_touch"

  primary_key

  column title : String

  belongs_to user : User, touch: true

  timestamps
end

class TouchCounterParent
  include Lustra::Model

  primary_key

  column children_count : Int32, presence: false

  timestamps
end

class TouchCounterChild
  include Lustra::Model

  primary_key

  belongs_to owner : TouchCounterParent, counter_cache: :children_count, touch: true
end

class PostWithOptionalUser
  include Lustra::Model

  self.table = "posts_with_optional_user"

  primary_key

  column title : String

  column content : String, presence: false

  belongs_to user : User?
end

class Tag
  include Lustra::Model

  column id : Int32, primary: true, presence: false

  column name : String

  has_many posts : Post, through: PostTag
end

class PostTag
  include Lustra::Model

  primary_key

  belongs_to post : Post, foreign_key_type: Int64?
  belongs_to tag : Tag, foreign_key_type: Int32?
end

class UserInfo
  include Lustra::Model

  column id : Int32, primary: true, presence: false

  belongs_to user : User, foreign_key_type: Int64?
  column registration_number : Int64
  column bio : String?
end

class Category
  include Lustra::Model

  column id : Int32, primary: true, presence: false

  column name : String

  has_many posts : Post
  has_many users : User, through: Post

  timestamps
end

class Comment
  include Lustra::Model

  primary_key

  column content : String

  belongs_to user : User, touch: :last_comment_at

  timestamps
end

class Picture
  include Lustra::Model

  primary_key

  column name : String

  belongs_to imageable : Employee | Product, polymorphic: true
  belongs_to employee : Employee, foreign_key: "imageable_id", polymorphic_type: "Employee"
  belongs_to product : Product, foreign_key: "imageable_id", polymorphic_type: "Product"
end

module PolymorphicSpec
  class Employee
    include Lustra::Model

    self.table = "polymorphic_spec_employees"

    primary_key

    column name : String

    has_many pictures : Picture, as: :imageable
  end

  class Product
    include Lustra::Model

    self.table = "polymorphic_spec_products"

    primary_key

    column name : String

    has_many pictures : Picture, as: :imageable
  end

  class Picture
    include Lustra::Model

    self.table = "polymorphic_spec_pictures"

    primary_key

    column name : String

    belongs_to imageable : PolymorphicSpec::Employee | PolymorphicSpec::Product, polymorphic: true
  end
end

class Relationship
  include Lustra::Model

  belongs_to master : User, foreign_key: "master_id"
  belongs_to dependency : User, foreign_key: "dependency_id"
end

class ModelWithUUID
  include Lustra::Model

  primary_key :id, type: :uuid

  self.table = "model_with_uuid"
end

class BigDecimalData
  include Lustra::Model

  column id : Int32, primary: true, presence: false
  column num1 : BigDecimal?
  column num2 : BigDecimal?
  column num3 : BigDecimal?
  column num4 : BigDecimal?
end

class FloatData
  include Lustra::Model

  primary_key

  column price : Float32     # PostgreSQL real type
  column latitude : Float64? # PostgreSQL double precision type
  column longitude : Float64?
  column temperature : Float32?
end

class RangeData
  include Lustra::Model

  primary_key

  column name : String?
  column int32_range : Range(Int32?, Int32?)?
  column int64_range : Range(Int64?, Int64?)?
  column numeric_range : Range(BigDecimal?, BigDecimal?)?
  column time_range : Range(Time?, Time?)?

  self.table = "range_data"
end

class ModelWithinAnotherSchema
  include Lustra::Model

  self.schema = "another_schema"
  self.table = "model_within_another_schemas"

  primary_key

  column title : String?
end

# Geometric test models
class Location
  include Lustra::Model

  primary_key

  column name : String

  # Using standard column syntax with PostgreSQL geometric types
  column coordinates : PG::Geo::Point
  column coverage_area : PG::Geo::Circle?
  column service_boundary : PG::Geo::Polygon?
  column bounding_box : PG::Geo::Box?

  timestamps
end

class Store
  include Lustra::Model

  primary_key

  column name : String
  column address : String?

  # Store location and delivery areas
  column location : PG::Geo::Point
  column delivery_area : PG::Geo::Polygon?
  column pickup_radius : PG::Geo::Circle?

  # Custom scopes
  scope("can_deliver_to") do |location|
    where { delivery_area.contains?(location) }
  end

  scope("pickup_available") do |location|
    where { pickup_radius.contains?(location) }
  end

  timestamps
end

class Route
  include Lustra::Model

  primary_key

  column name : String
  column description : String?

  # Route geometry
  column route_path : PG::Geo::Path
  column main_segment : PG::Geo::LineSegment?

  timestamps
end

class ModelSpecMigration123
  include Lustra::Migration

  def change(dir)
    create_enum(:gender_type, GenderType)

    create_table "categories" do |t|
      t.column "name", "string"

      t.references to: "categories", name: "category_id", null: true, on_delete: "set null"

      t.timestamps
    end

    create_table "tags", id: :serial do |t|
      t.column "name", "string", unique: true, null: false
    end

    create_table "users" do |t|
      t.column "first_name", "string"
      t.column "last_name", "string"
      t.column "middle_name", type: "varchar(32)"

      t.column :gender, :gender_type

      t.column "active", "bool", null: true
      t.column "posts_count", "int", null: false, default: "0"

      t.column "notification_preferences", "jsonb", index: "gin", default: "'{}'"
      t.column "last_comment_at", "timestamp"

      t.timestamps
    end

    create_table "employees" do |t|
      t.column "name", "string", null: false
    end

    create_table "products" do |t|
      t.column "name", "string", null: false
    end

    create_table "relationships", id: false do |t|
      t.references to: "users", name: "master_id", on_delete: "cascade", null: false, primary: true
      t.references to: "users", name: "dependency_id", on_delete: "cascade", null: false, primary: true

      t.index ["master_id", "dependency_id"], using: :btree, unique: true
    end

    create_table "posts" do |t|
      t.column "title", "string", index: true

      t.column "tags_list", "string", array: true, index: "gin", default: "ARRAY['post', 'arr 2']"
      t.column "flags_other_column_name", "bigint", array: true, index: "gin", default: "'{}'::bigint[]"

      t.column "published", "boolean", default: "true", null: false
      t.column "content", "string", default: "''", null: false

      t.references to: "users", name: "user_id", on_delete: "cascade"
      t.references to: "categories", name: "category_id", null: true, on_delete: "set null"
    end

    create_table "posts_with_touch" do |t|
      t.column "title", "string", null: false

      t.references to: "users", name: "user_id", on_delete: "cascade"

      t.timestamps
    end

    create_table "touch_counter_parents" do |t|
      t.column "children_count", "int", null: false, default: "0"

      t.timestamps
    end

    create_table "touch_counter_children" do |t|
      t.references to: "touch_counter_parents", name: "owner_id", on_delete: "cascade"
    end

    create_table "posts_with_optional_user" do |t|
      t.column "title", "string", null: false

      t.references to: "users", name: "user_id", on_delete: "cascade", null: true

      t.timestamps
    end

    create_table "comments" do |t|
      t.column "content", "string", null: false

      t.references to: "users", name: "user_id", on_delete: "cascade"

      t.timestamps
    end

    create_table "pictures" do |t|
      t.column "name", "string", null: false
      t.column "imageable_id", "bigint", null: false
      t.column "imageable_type", "string", null: false
    end

    create_table "polymorphic_spec_employees" do |t|
      t.column "name", "string", null: false
    end

    create_table "polymorphic_spec_products" do |t|
      t.column "name", "string", null: false
    end

    create_table "polymorphic_spec_pictures" do |t|
      t.column "name", "string", null: false
      t.column "imageable_id", "bigint", null: false
      t.column "imageable_type", "string", null: false
    end

    create_table "post_tags" do |t|
      t.references to: "tags", name: "tag_id", on_delete: "cascade", null: false, primary: true
      t.references to: "posts", name: "post_id", on_delete: "cascade", null: false, primary: true

      t.index ["tag_id", "post_id"], using: :btree
    end

    create_table "user_infos" do |t|
      t.references to: "users", name: "user_id", on_delete: "cascade", null: true

      t.column "registration_number", "int64", index: true
      t.column "bio", "string", null: true

      t.timestamps
    end

    create_table "callback_test_models" do |t|
      t.column "name", "string", null: false
      t.column "callback_triggered", "boolean", default: "false", null: false

      t.timestamps
    end

    dir.up { execute "CREATE SCHEMA another_schema" }

    create_table "model_within_another_schemas", schema: "another_schema" do |t|
      t.column "title", "string", null: true
    end

    create_table("model_with_uuid", id: :uuid) { }

    create_table :big_decimal_data do |t|
      t.column "num1", "bigdecimal", index: true
      t.column "num2", "numeric(18, 8)"
      t.column "num3", "numeric(9)"
      t.column "num4", "numeric(8)"

      t.timestamps
    end

    create_table :float_data do |t|
      t.column "price", "real", null: false
      t.column "latitude", "double precision", null: true
      t.column "longitude", "double precision", null: true
      t.column "temperature", "real", null: true

      t.timestamps
    end

    create_table :range_data do |t|
      t.column "name", "string", null: true
      t.column "int32_range", "int4range", null: true
      t.column "int64_range", "int8range", null: true
      t.column "numeric_range", "numrange", null: true
      t.column "time_range", "tsrange", null: true

      t.timestamps
    end

    # Geometric test tables
    create_table :locations do |t|
      t.column "name", "string", null: false
      t.column "coordinates", "point", null: false
      t.column "coverage_area", "circle", null: true
      t.column "service_boundary", "polygon", null: true
      t.column "bounding_box", "box", null: true

      # Create spatial indexes
      t.index("coordinates", using: "gist")
      t.index("coverage_area", using: "gist")

      t.timestamps
    end

    create_table :stores do |t|
      t.column "name", "string", null: false
      t.column "address", "string", null: true
      t.column "location", "point", null: false
      t.column "delivery_area", "polygon", null: true
      t.column "pickup_radius", "circle", null: true

      # Create spatial indexes
      t.index("location", using: "gist")
      t.index("delivery_area", using: "gist")

      t.timestamps
    end

    create_table :routes do |t|
      t.column "name", "string", null: false
      t.column "description", "string", null: true
      t.column "route_path", "path", null: false
      t.column "main_segment", "lseg", null: true

      t.timestamps
    end

    # Add exclusion constraint to prevent overlapping store delivery areas
    add_exclusion_constraint("stores", "delivery_area")
  end
end

def self.reinit_example_models
  reinit_migration_manager

  ModelSpecMigration123.new.apply
end
