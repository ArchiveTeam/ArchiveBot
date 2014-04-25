require 'yaml'

module SharedConfig
  module_function

  def config
    # For maximum fun, check out https://github.com/tenderlove/psych/issues/119
    # re: the development of safe_load
    YAML.safe_load(File.read(File.expand_path('../shared_config.yml', __FILE__)))
  end

  def log_channel
    config['channels']['log']
  end

  def job_channel(ident)
    "#{job_channel_prefix}#{ident}"
  end

  def job_channel_prefix
    config['channels']['job_prefix']
  end

  def irc_server_uri
    config['irc']['server_uri']
  end

  def irc_nick
    config['irc']['nick']
  end

  def irc_channels
    puts config['irc'].inspect
    config['irc']['channels']
  end
end
