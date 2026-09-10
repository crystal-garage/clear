# This module provides the callback system for `Lustra::Model`, allowing you to hook into
# model lifecycle events like `:create`, `:update`, `:validate`, etc.
module Lustra::Model::HasHooks
  # This performs these operations:
  #
  # - Call triggers `before` the event
  # - Yield the given block
  # - Call triggers `after` the event
  #
  # ```
  # model.with_triggers("email_sent") do |m|
  #   model.send_email
  # end
  # ```
  #
  # Returns `self`
  def with_triggers(event_name, &)
    Lustra::SQL.transaction(self.class.connection) do |cnx|
      trigger_before_events(event_name)
      yield(cnx)
      trigger_after_events(event_name)
    end
    self
  end

  # Triggers the events hooked before `event_name`
  def trigger_before_events(event_name)
    Lustra::Model::EventManager.trigger(self.class, :before, event_name, self)
  end

  # Triggers the events hooked after `event_name`
  def trigger_after_events(event_name)
    Lustra::Model::EventManager.trigger(self.class, :after, event_name, self)
  end

  module ClassMethods
    # Register a callback to be executed BEFORE the specified lifecycle event
    #
    # `event_name` - the lifecycle event (`:create`, `:update`, `:validate`, etc.)
    # `block` - the callback block to execute
    #
    # Note: The block parameter has type `Lustra::Model`. Use `.as(YourModel)` to access
    # model-specific methods and columns.
    #
    # Example:
    # ```
    # before(:validate) do |model|
    #   user = model.as(User)
    #   user.email = user.email.downcase
    # end
    # ```
    def before(event_name : Symbol, &block : Lustra::Model -> Nil)
      Lustra::Model::EventManager.attach(self, :before, event_name, block)
    end

    # Register a callback to be executed AFTER the specified lifecycle event
    #
    # `event_name` - the lifecycle event (`:create`, `:update`, `:validate`, etc.)
    # `block` - the callback block to execute
    #
    # Note: The block parameter has type `Lustra::Model`. Use `.as(YourModel)` to access
    # model-specific methods and columns.
    #
    # Example:
    # ```
    # after(:create) do |model|
    #   user = model.as(User)
    #   user.send_welcome_email
    # end
    # ```
    def after(event_name : Symbol, &block : Lustra::Model -> Nil)
      Lustra::Model::EventManager.attach(self, :after, event_name, block)
    end
  end

  # Macro version of `before` - calls a method instead of a block
  #
  # Example: `before(:validate, :sanitize_data)`
  # Equivalent to: `before(:validate) { |model| model.as(User).sanitize_data }`
  #
  # The macro automatically casts to the correct type for you.
  macro before(event_name, method_name)
    before({{ event_name }}) { |mdl|
      mdl.as({{ @type }}).{{ method_name.id }}
    }
  end

  # Macro version of `after` - calls a method instead of a block
  #
  # Example: `after(:create, :send_welcome_email)`
  # Equivalent to: `after(:create) { |model| model.as(User).send_welcome_email }`
  #
  # The macro automatically casts to the correct type for you.
  macro after(event_name, method_name)
    after({{ event_name }}) { |mdl|
      mdl.as({{ @type }}).{{ method_name.id }}
    }
  end
end
