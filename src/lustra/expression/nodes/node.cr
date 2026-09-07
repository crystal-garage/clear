require "../expression"

# Mother class of all the rendering nodes
abstract class Lustra::Expression::Node
  macro define_operator(op_name, sql_name, null = false)
    def {{ op_name.id }}(any : Node) : Node
      Node::DoubleOperator.new(self, any, "{{ sql_name.id }}")
    end

    {% if null %}
      def {{ op_name.id }}(some_nil : Nil) : Node
        Node::DoubleOperator.new(self, Null.new, {{ null }} )
      end
    {% end %}

    def {{ op_name.id }}(any : T) : Node forall T
      Node::DoubleOperator.new(self, Literal.new(any), "{{ sql_name.id }}")
    end
  end

  {% for op in [">", ">=", "<", "<=", "+", "-", "*", "/"] %}
    define_operator({{ op }}, {{ op }})
  {% end %}

  def =~(any : Node) : Node
    Node::DoubleOperator.new(self, any, "~")
  end

  def !~(any : Node) : Node
    Node::DoubleOperator.new(self, any, "!~")
  end

  def =~(regexp : Regex) : Node
    if regexp.options.ignore_case?
      Node::DoubleOperator.new(self, Literal.new(regexp.source), "~*")
    else
      Node::DoubleOperator.new(self, Literal.new(regexp.source), "~")
    end
  end

  def !~(regexp : Regex) : Node
    if regexp.options.ignore_case?
      Node::DoubleOperator.new(self, Literal.new(regexp.source), "!~*")
    else
      Node::DoubleOperator.new(self, Literal.new(regexp.source), "!~")
    end
  end

  define_operator("!=", "<>", null: "IS NOT")
  define_operator("==", "=", null: "IS")
  define_operator("like", "LIKE")
  define_operator("ilike", "ILIKE")
  define_operator("&", "AND")
  define_operator("|", "OR")

  def in?(range : Range(B, E)) forall B, E
    range_begin = range.begin.nil? ? nil : Lustra::Expression[range.begin]
    range_end = range.end.nil? ? nil : Lustra::Expression[range.end]

    Node::InRange.new(self,
      range_begin..range_end,
      range.exclusive?)
  end

  def in?(arr : Array(T)) forall T
    Node::InArray.new(self, arr.map { |x| Lustra::Expression[x] })
  end

  def in?(tuple : Tuple(*T)) forall T
    in?(tuple.to_a)
  end

  def in?(request : ::Lustra::SQL::SelectBuilder)
    Node::InSelect.new(self, request)
  end

  def between?(a, b)
    Node::Between.new(self, a, b)
  end

  def after?(other)
    self > other
  end

  def before?(other)
    self < other
  end

  @[Deprecated("Use #between? instead.")]
  def between(a, b)
    between?(a, b)
  end

  def -
    Node::Minus.new(self)
  end

  def ~
    Node::Not.new(self)
  end

  def null? : Node
    Node::DoubleOperator.new(self, Null.new, "IS")
  end

  def true? : Node
    Node::DoubleOperator.new(self, Literal.new(true), "=")
  end

  def false? : Node
    Node::DoubleOperator.new(self, Literal.new(false), "=")
  end

  abstract def resolve : String
end
