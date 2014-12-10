module ActsAsMessageable
  module Model

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      mattr_accessor :messages_class_name, :group_messages

      # Method make ActiveRecord::Base object messageable
      # @param [Symbol] :table_name - table name for messages
      # @param [String] :class_name - message class name
      # @param [Array, Symbol] :required - required fields in message
      # @param [Symbol] :dependent - dependent option from ActiveRecord has_many method
      def acts_as_messageable(options = {})
        default_options = {
          :table_name => "messages",
          :class_name => "ActsAsMessageable::Message",
          :required => [:topic, :body],
          :dependent => :nullify,
          :group_messages => false,
        }
        options = default_options.merge(options)

        has_many  :received_messages_relation,
                  :as => :received_messageable,
                  :class_name => options[:class_name],
                  :dependent => options[:dependent]

        has_many  :sent_messages_relation,
                  :as => :sent_messageable,
                  :class_name => options[:class_name],
                  :dependent => options[:dependent]

        self.messages_class_name = options[:class_name].constantize
        self.messages_class_name.has_ancestry

        if self.messages_class_name.respond_to?(:table_name=)
          self.messages_class_name.table_name = options[:table_name]
          self.messages_class_name.initialize_scopes
        else
          self.messages_class_name.set_table_name(options[:table_name])
          ActiveSupport::Deprecation.warn("Calling set_table_name is deprecated. Please use `self.table_name = 'the_name'` instead.")
        end

        self.messages_class_name.required = Array.wrap(options[:required])
        self.messages_class_name.validates_presence_of self.messages_class_name.required
        self.group_messages = options[:group_messages]

        include ActsAsMessageable::Model::InstanceMethods
    end

    # Method recognize real object class
    # @return [ActiveRecord::Base] class or relation object
    def resolve_active_record_ancestor
      self.reflect_on_association(:received_messages_relation).active_record
    end

    end

    module InstanceMethods
      # @return [ActiveRecord::Relation] all messages connected with user
      def messages(trash = false)
        result = self.class.messages_class_name.connected_with(self, trash)
        result.relation_context = self

        result
      end

      # @return [ActiveRecord::Relation] returns all messages from inbox
      def received_messages
        result = ActsAsMessageable.rails_api.new(received_messages_relation)
        result = result.scoped.where(:recipient_delete => false)
        result.relation_context = self

        result
      end

      # @return [ActiveRecord::Relation] returns all messages from outbox
      def sent_messages
        result = ActsAsMessageable.rails_api.new(sent_messages_relation)
        result = result.scoped.where(:sender_delete => false)
        result.relation_context = self

        result
      end

      # @return [ActiveRecord::Relation] returns all messages from trash
      def deleted_messages
        messages true
      end

      # Method sens message to another user
      # @param [ActiveRecord::Base] to
      # @param [String] topic
      # @param [String] body
      #
      # @return [ActsAsMessageable::Message] the message object
      def send_message(to, message_type, *args)
        message_type = self.class.messages_class_name if message_type.nil?
        raise "Is not subclass of #{self.class.messages_class_name}: #{message_type.inspect}" if message_type.nil? || !(message_type <= self.class.messages_class_name)        
        message_attributes = {}
        
        case args.first
          when String
            self.class.messages_class_name.required.each_with_index do |attribute, index|
              message_attributes[attribute] = args[index]
            end
          when Hash
            message_attributes = args.first
        end
        

        message = message_type.new message_attributes
        message.received_messageable = to
        message.sent_messageable = self
         
        yield message if block_given?
        
        message.save
        message
      end

      # Method send message to another user
      # and raise exception in case of validation errors
      # @param [ActiveRecord::Base] to
      # @param [String] topic
      # @param [String] body
      #
      # @return [ActsAsMessageable::Message] the message object
      def send_message!(to, message_type, *args)
        send_message(to, message_type, *args).save!
      end

      # Reply to given message
      # @param [ActsAsMessageable::Message] message
      # @param [String] topic
      # @param [String] body
      #
      # @return [ActsAsMessageable::Message] a message that is a response to a given message
      def reply_to(message, message_type, *args)
        current_user = self
        
        if message.participant?(current_user)
          reply_message = send_message(message.real_receiver(current_user), message_type, *args)
          reply_message.parent = message
          reply_message.save
          reply_message
        end
      end

      # Mark message as deleted
      def delete_message(message)
        current_user = self

        case current_user
          when message.to
            attribute = message.recipient_delete ? :recipient_permanent_delete : :recipient_delete
          when message.from
            attribute = message.sender_delete ? :sender_permanent_delete : :sender_delete
          else
            raise "#{current_user} can't delete this message"
        end

        message.update_attributes!(attribute => true)
      end

      # Mark message as restored
      def restore_message(message)
        current_user = self

        case current_user
          when message.to
            attribute = :recipient_delete
          when message.from
            attribute = :sender_delete
          else
            raise "#{current_user} can't restore this message"
        end

        message.update_attributes!(attribute => false)
      end
    end
  end
end
