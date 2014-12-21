require 'ffi-rzmq'

module ArchiveBot
  module ZmqUtils
    def zmq_ok?(ret)
      ZMQ::Util.resultcode_ok?(ret).tap do |ret|
        if !ret
          $stderr.puts "ZeroMQ operation failed: errno [#{ZMQ::Util.errno}] description [#{ZMQ::Util.error_string}]"
        end
      end
    end

    alias_method :zmq_error_check, :zmq_ok?
  end
end
