class Tag
  include Clear::Model

  column id : Int32, primary: true, presence: false

  column name : String

  has_many posts : Post, through: :post_tags, foreign_key: :post_id, own_key: :tag_id
end

class PostTag
  include Clear::Model

  belongs_to post : Post, key_type: Int32?
  belongs_to tag : Tag, key_type: Int32?
end

class Category
  include Clear::Model

  column id : Int32, primary: true, presence: false

  column name : String

  has_many posts : Post
  has_many users : User, through: Post, foreign_key: :user_id, own_key: :category_id

  timestamps
end

class Post
  include Clear::Model

  column id : Int32, primary: true, presence: false

  column title : String

  column tags : Array(String), presence: false
  column flags : Array(Int64), presence: false, column_name: "flags_other_column_name"

  column content : String, presence: false

  column published : Bool, presence: false

  scope("published") { where published: true }

  def validate
    ensure_than(title, "is not empty", &.size.>(0))
  end

  has_many post_tags : PostTag, foreign_key: "post_id"
  has_many tag_relations : Tag, through: :post_tags, foreign_key: :tag_id, own_key: :post_id

  belongs_to user : User, key_type: Int32?
  belongs_to category : Category, key_type: Int32?
end

class UserInfo
  include Clear::Model

  column id : Int32, primary: true, presence: false

  belongs_to user : User, key_type: Int32?
  column registration_number : Int64
end

class User
  include Clear::Model

  column id : Int32, primary: true, presence: false

  column first_name : String
  column last_name : String?
  column middle_name : String? # , mass_assign: false

  column active : Bool?

  column notification_preferences : JSON::Any, presence: false

  has_many posts : Post, foreign_key: "user_id"
  has_one info : UserInfo?, foreign_key: "user_id"
  has_many categories : Category, through: :posts, own_key: :user_id, foreign_key: :category_id

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

class Relationship
  include Clear::Model

  primary_key

  belongs_to master : User, foreign_key: "master_id"
  belongs_to dependency : User, foreign_key: "dependency_id"
end

class ModelWithUUID
  include Clear::Model

  primary_key :id, type: :uuid

  self.table = "model_with_uuid"
end

class BigDecimalData
  include Clear::Model

  column id : Int32, primary: true, presence: false
  column num1 : BigDecimal?
  column num2 : BigDecimal?
  column num3 : BigDecimal?
  column num4 : BigDecimal?
end

# class ModelWithinAnotherSchema
#   include Clear::Model

#   self.schema = "another_schema"
#   self.table = "model_within_another_schemas"

#   primary_key

#   column title : String?
# end

class ModelSpecMigration123
  include Clear::Migration

  def change(dir)
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

      t.column "active", "bool", null: true

      t.column "middle_name", type: "varchar(32)"

      t.column "notification_preferences", "jsonb", index: "gin", default: "'{}'"

      t.timestamps
    end

    create_table "relationships" do |t|
      t.references to: "users", name: "master_id", on_delete: "cascade", null: false, primary: true
      t.references to: "users", name: "dependency_id", on_delete: "cascade", null: false, primary: true

      t.index ["master_id", "dependency_id"], using: :btree, unique: true
    end

    create_table "posts" do |t|
      t.column "title", "string", index: true

      t.column "tags", "string", array: true, index: "gin", default: "ARRAY['post', 'arr 2']"
      t.column "flags_other_column_name", "bigint", array: true, index: "gin", default: "'{}'::bigint[]"

      t.column "published", "boolean", default: "true", null: false
      t.column "content", "string", default: "''", null: false

      t.references to: "users", name: "user_id", on_delete: "cascade"
      t.references to: "categories", name: "category_id", null: true, on_delete: "set null"
    end

    create_table "post_tags", id: false do |t|
      t.references to: "tags", name: "tag_id", on_delete: "cascade", null: false, primary: true
      t.references to: "posts", name: "post_id", on_delete: "cascade", null: false, primary: true

      t.index ["tag_id", "post_id"], using: :btree
    end

    create_table "user_infos" do |t|
      t.references to: "users", name: "user_id", on_delete: "cascade", null: true

      t.column "registration_number", "int64", index: true

      t.timestamps
    end

    # dir.up { execute "CREATE SCHEMA another_schema" }

    # create_table "model_within_another_schemas", schema: "another_schema" do |t|
    #   t.column "title", "string", null: true
    # end

    create_table("model_with_uuid", id: :uuid) { }

    create_table :big_decimal_data do |t|
      t.column "num1", "bigdecimal", index: true
      t.column "num2", "numeric(18, 8)"
      t.column "num3", "numeric(9)"
      t.column "num4", "numeric(8)"

      t.timestamps
    end
  end
end

def self.reinit_example_models
  reinit_migration_manager
  ModelSpecMigration123.new.apply((Clear::Migration::Direction::UP))
end
