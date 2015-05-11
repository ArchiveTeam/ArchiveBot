module PipelineOptions
  def run_post_registration_hooks(m, job, params)
    return unless authorized?(m)

    if params[:pipeline]
      pipeline = params[:pipeline]
      reply m, %Q{Job will run on a pipeline whose name contains "#{pipeline}".}
    end

    phantomjs_triggers = [
      :phantomjs,
      :phantomjs_scroll,
      :phantomjs_wait,
      :no_phantomjs_smart_scroll
    ]

    if phantomjs_triggers.any? { |t| params[t] }
      job.use_phantomjs(params[:phantomjs_scroll], params[:phantomjs_wait],
                        params[:no_phantomjs_smart_scroll])

      reply m, "Job will run using PhantomJS."
      reply m, "PhantomJS settings: #{job.phantomjs_info}"
    end

    if params[:youtube_dl]
      job.use_youtube_dl
    end

    if params[:no_offsite_links]
      job.no_offsite_links!

      reply m, 'Offsite links will not be grabbed.'
    end

    super
  end
end
