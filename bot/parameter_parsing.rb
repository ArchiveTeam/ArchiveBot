module ParameterParsing
  def parse_params(str)
    str.split(/\s+/).each_with_object({}) do |p, h|
      k, v = p.split('=')

      # If there's no value, ignore the parameter.
      next if !v

      # Remove the --, and represent dashes as underscores.
      k.sub!(/\A--/, '').gsub!('-', '_')

      # Split comma-separated values.
      vs = v.split(/\s*,\s*/)

      h[k] = vs
    end
  end
end
