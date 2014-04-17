module PipelineOptions
  def run_post_registration_hooks(m, job, params)
    return unless authorized?(m)

    if params[:pipeline]
      pipeline = h[:pipeline].first
      reply m, "Job will run on pipeline #{pipeline}."
    end

    if params[:phantomjs]
      job.use_js_grabber
      reply m, "Job will run using PhantomJS."
    end

    super
  end
end
