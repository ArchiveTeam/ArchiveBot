module PipelineOptions
  def run_post_registration_hooks(m, job, params)
    return unless authorized?(m)

    messages = []

    if params[:pipeline]
      pipeline = params[:pipeline]
      messages << "pipeline: /#{pipeline}/"
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

      messages << "phantomjs: yes, #{job.phantomjs_info}"
    end

    if params[:youtube_dl]
      job.use_youtube_dl
      messages << 'youtube-dl: yes (please read https://git.io/vUjC0)'
    end

    if params[:no_offsite_links]
      job.no_offsite_links!
      messages << 'offsite links: no'
    end

    if !messages.empty?
      reply m, "Options: #{messages.join('; ')}"
    end

    super
  end
end
