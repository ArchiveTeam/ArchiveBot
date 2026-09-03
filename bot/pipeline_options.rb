module PipelineOptions
  def run_post_registration_hooks(m, job, params)
    messages = []

    if params[:pipeline]
      pipeline = params[:pipeline]
      messages << "pipeline: /#{pipeline}/"
    end

    if params[:youtube_dl]
      job.use_youtube_dl
      messages << 'youtube-dl: yes (please read https://git.io/vUjC0)'
    end

    if params[:no_offsite_links]
      job.no_offsite_links!
      messages << 'offsite links: no'
    end

    if params[:no_cookies]
      job.no_cookies!
      messages << 'use cookies: no'
    end

    if !messages.empty?
      reply m, "Options: #{messages.join('; ')}"
    end

    super
  end
end
