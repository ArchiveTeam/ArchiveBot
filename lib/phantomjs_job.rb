##
# Methods for running jobs with PhantomJS.
module PhantomJSJob
  ##
  # Maximum number of times to have PhantomJS scroll a page.  Defaults to 100.
  attr_reader :phantomjs_scroll

  ##
  # Seconds to wait between PhantomJS requests.  Defaults to 2.0.
  attr_reader :phantomjs_wait

  ##
  # If true, forces the page to be scrolled #phantomjs_scroll number of times.
  # If false, PhantomJS' end-of-page detection will be used.
  attr_reader :no_phantomjs_smart_scroll

  ##
  # Tells a pipeline to use PhantomJS to access a site.
  def use_phantomjs(scroll = nil, wait = nil, no_smart_scroll = nil)
    @phantomjs_wait = wait || 2.0
    @phantomjs_scroll = scroll || 100
    @no_phantomjs_smart_scroll = no_smart_scroll || false

    params = {
      grabber: 'phantomjs',
      phantomjs_wait: phantomjs_wait,
      phantomjs_scroll: phantomjs_scroll,
      no_phantomjs_smart_scroll: no_phantomjs_smart_scroll
    }.select { |k, v| v }.flatten

    redis.hmset(ident, *params)
  end

  ##
  # Returns PhantomJS operational parameters in human-readable format.
  def phantomjs_info
    info = []

    info << "Max scroll count: #{phantomjs_scroll}"
    info << "Wait time: #{phantomjs_wait} sec"
    info << "Use smart scroll: #{!no_phantomjs_smart_scroll}"

    info.join(', ')
  end

  ##
  # Retrieves PhantomJS attributes.  Invoked from Job#from_hash.
  def from_hash(h)
    @phantomjs_wait = h['phantomjs_wait']
    @phantomjs_scroll = h['phantomjs_scroll']
    @no_phantomjs_smart_scroll = h['no_phantomjs_smart_scroll']

    super
  end

  ##
  # Returns PhantomJS attributes in a Job's JSON format.  Invoked from Job#as_json.
  def as_json
    { 'phantomjs_wait' => phantomjs_wait,
      'phantomjs_scroll' => phantomjs_scroll,
      'no_phantomjs_smart_scroll' => no_phantomjs_smart_scroll
    }.merge(super)
  end
end
