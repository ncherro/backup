# encoding: utf-8

module Backup
  module RemoteDatabase
    class Base
      include Backup::Utilities::Helpers
      include Backup::Configuration::Helpers

      attr_reader :model, :database_id

      ##
      # Base path on the remote where backup package files will be stored.
      attr_accessor :remote_path

      ##
      # SSH User
      #
      # If the user running the backup is not the same user that needs to
      # authenticate with the remote server, specify the user here.
      #
      # The user must have SSH keys setup for passphrase-less access to the
      # remote. If the SSH User does not have passphrase-less keys, or no
      # default keys in their `~/.ssh` directory, you will need to use the
      # `-i` option in `:additional_ssh_options` to specify the
      # passphrase-less key to use.
      attr_accessor :ssh_user

      ##
      # SSH port
      #
      # For this specifies the SSH port to use and defaults to 22.
      attr_accessor :ssh_port

      ##
      # Server Address
      attr_accessor :ssh_host

      ##
      # Additional SSH Options
      #
      # Used to supply a String or Array of options to be passed to the SSH
      # command
      #
      # For example, if you need to supply a specific SSH key for the `ssh_user`,
      # you would set this to: "-i '/path/to/id_rsa'". Which would produce:
      #
      #   ssh -p 22 -i '/path/to/id_rsa'
      #
      # Arguments may be single-quoted, but should not contain any double-quotes.
      attr_accessor :additional_ssh_options


      ##
      # If given, +database_id+ will be appended to the #dump_filename.
      # This is required if multiple Databases of the same class are added to
      # the model.
      def initialize(model, database_id = nil)
        @model = model
        @database_id = database_id.to_s.gsub(/\W/, '_') if database_id
        load_defaults!
      end

      def perform!
        log!(:started)
        prepare!
      end

      private

      def prepare!
        # ssh in, and make sure the dump dir exists
        #
        run "#{ utility(:ssh) } #{ ssh_transport_args } #{ ssh_host } " +
               %Q["mkdir -p '#{ dest_path }'"]
      end

      def ssh_transport_args
        args = "-p #{ ssh_port } "
        args << "-l #{ ssh_user } " if ssh_user
        args << Array(additional_ssh_options).join(' ')
        args.rstrip
      end

      ##
      # Remove any preceeding '~/', since this is on the remote,
      # and remove any trailing `/`.
      def dest_path
        @dest_path ||= remote_path.sub(/^~\//, '').sub(/\/$/, '')
      end

      ##
      # Sets the base filename for the final dump file to be saved in +dump_path+,
      # based on the class name. e.g. databases/MySQL.sql
      #
      # +database_id+ will be appended if it is defined.
      # e.g. databases/MySQL-database_id.sql
      #
      # If multiple Databases of the same class are defined and no +database_id+
      # is defined, the user will be warned and one will be auto-generated.
      #
      # Model#initialize calls this method *after* all defined databases have
      # been initialized so `backup check` can report these warnings.
      def dump_filename
        @dump_filename ||= begin
          unless database_id
            if model.databases.select {|d| d.class == self.class }.count > 1
              sleep 1; @database_id = Time.now.to_i.to_s[-5, 5]
              Logger.warn Errors::Database::ConfigurationError.new(<<-EOS)
                Database Identifier Missing

                When multiple Databases are configured in a single Backup Model
                that have the same class (MySQL, PostgreSQL, etc.), the optional
                +database_id+ must be specified to uniquely identify each instance.
                e.g. database MySQL, :database_id do |db|
                This will result in an output file in your final backup package like:
                databases/MySQL-database_id.sql

                Backup has auto-generated an identifier (#{ database_id }) for this
                database dump and will now continue.
              EOS
            end
          end

          self.class.name.split('::').last + (database_id ? "-#{ database_id }" : '')
        end
      end

      def database_name
        @database_name ||= self.class.to_s.sub('Backup::', '') +
            (database_id ? " (#{ database_id })" : '')
      end

      def log!(action)
        msg = case action
              when :started then 'Started...'
              when :finished then 'Finished!'
              end
        Logger.info "#{ database_name } #{ msg }"
      end
    end
  end
end
