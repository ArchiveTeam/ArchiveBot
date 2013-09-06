require 'shellwords'
require 'tmpdir'

module Strategies
  # Downloads sites using wget-lua.
  class Wget
    attr_reader :ident
    attr_reader :uri

    def initialize(ident, uri)
      @ident = ident
      @uri = uri
    end

    def run
      dir = Dir.mktmpdir

      begin
        io = start(dir)

        loop do
          info = io.readline.split("\t")
          yield info
        end
      rescue EOFError
        # ignore it
      ensure
        Dir.rmdir(dir)
      end
    end

    def start(dir)
      IO.popen([
        wget_lua,
        "-U", user_agent,
        "--lua-script", File.expand_path('../wget_comm.lua', __FILE__),
        "--output-document", "#{dir}/wget.tmp",
        "-o", "#{dir}/wget.log",
        "--truncate-output",
        "--page-requisites",
        "--span-hosts",
        "--no-parent",
        "-r",
        "-l", "inf",
        "--no-remove-listing",
        "-e", "robots=off",
        "--warc-file", "#{dir}/#{ident}",
        "--warc-header", "operator: Archive Team",
        "--warc-header", "generator: ArchiveBot",
        "--waitretry", "5",
        "--timeout", "60",
        "--random-wait",
        "--wait", "1",
        uri
      ])
    end

    private

    def user_agent
      %q{Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:23.0) Gecko/20100101 Firefox/23.0}
    end

    def wget_lua
      File.expand_path('../wget-lua', __FILE__)
    end
  end
end

if $0 == __FILE__
  if !ARGV[0]
    puts "Usage: #$0 URL"
    exit 1
  end

  s = Strategies::Wget.new('foo', ARGV[0])
  s.run do |info|
    print (" " * 132) + "\r"
    print "#{info[0]}: #{info[1]}, #{info[2]}\r"
  end
end
