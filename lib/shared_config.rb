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

  def job_channel
    config['channels']['job']
  end
end
