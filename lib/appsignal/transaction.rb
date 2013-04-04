require 'socket'
require 'appsignal/transaction/transaction_formatter'
require 'appsignal/transaction/params_sanitizer'

module Appsignal
  class Transaction
    # Based on what Rails uses + some variables we'd like to show
    ENV_METHODS = %w(CONTENT_LENGTH AUTH_TYPE GATEWAY_INTERFACE
    PATH_TRANSLATED REMOTE_HOST REMOTE_IDENT REMOTE_USER REMOTE_ADDR
    REQUEST_METHOD SERVER_NAME SERVER_PORT SERVER_PROTOCOL

    HTTP_X_REQUEST_START HTTP_X_MIDDLEWARE_START HTTP_X_QUEUE_START
    HTTP_X_QUEUE_TIME HTTP_X_HEROKU_QUEUE_WAIT_TIME HTTP_X_APPLICATION_START
    HTTP_ACCEPT HTTP_ACCEPT_CHARSET HTTP_ACCEPT_ENCODING HTTP_ACCEPT_LANGUAGE
    HTTP_CACHE_CONTROL HTTP_CONNECTION HTTP_USER_AGENT HTTP_FROM HTTP_NEGOTIATE
    HTTP_PRAGMA HTTP_REFERER).freeze

    def self.create(key, env)
      Thread.current[:appsignal_transaction_id] = key
      Appsignal.transactions[key] = Appsignal::Transaction.new(key, env)
    end

    def self.current
      Appsignal.transactions[Thread.current[:appsignal_transaction_id]]
    end

    attr_reader :id, :events, :process_action_event, :action, :exception, :env,
      :fullpath, :time

    def initialize(id, env)
      @id = id
      @events = []
      @process_action_event = nil
      @exception = nil
      @env = env
    end

    def sanitized_environment
      @sanitized_environment ||= {}
    end

    def sanitized_session_data
      @sanitized_session_data ||= {}
    end

    def request
      ActionDispatch::Request.new(@env)
    end

    def set_process_action_event(event)
      @process_action_event = event
      if event && event.payload
        @action = "#{event.payload[:controller]}##{event.payload[:action]}"
      end
    end

    def add_event(event)
      @events << event
    end

    def add_exception(ex)
      @time = Time.now.utc.to_f
      @exception = ex
    end

    def exception?
      !!exception
    end

    def slow_request?
      return false unless process_action_event && process_action_event.payload
      Appsignal.config[:slow_request_threshold] <=
        process_action_event.duration
    end

    def slower?(transaction)
      process_action_event.duration > transaction.process_action_event.duration
    end

    def truncate!
      process_action_event.payload.clear
      events.clear
      sanitized_environment.clear
      sanitized_session_data.clear
      @env = nil
    end

    def convert_values_to_primitives!
      Appsignal::ParamsSanitizer.sanitize!(@process_action_event.payload) if @process_action_event
      @events.each { |o| Appsignal::ParamsSanitizer.sanitize!(o.payload) }
      add_sanitized_context!
    end

    def type
      return :exception if exception?
      return :slow_request if slow_request?
      :regular_request
    end

    def to_hash
      TransactionFormatter.new(self).to_hash
    end

    def complete!
      Thread.current[:appsignal_transaction_id] = nil
      current_transaction = Appsignal.transactions.delete(@id)
      if process_action_event || exception?
        Appsignal.enqueue(current_transaction)
      end
    end

    protected

    def add_sanitized_context!
      sanitize_environment!
      sanitize_session_data!
      @env = nil
    end

    def sanitize_environment!
      env.each do |key, value|
        sanitized_environment[key] = value if ENV_METHODS.include?(key)
      end
    end

    def sanitize_session_data!
      @sanitized_session_data =
        Appsignal::ParamsSanitizer.sanitize(request.session)
      @fullpath = request.fullpath
    end

  end
end
