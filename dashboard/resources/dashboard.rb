class Dashboard < Webmachine::Resource
  def to_html
    File.read(File.expand_path('../../dashboard.html', __FILE__))
  end
end
