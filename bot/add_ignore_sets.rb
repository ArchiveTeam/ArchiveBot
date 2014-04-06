module AddIgnoreSets
  def run_post_registration_hooks(m, job, params)
    return unless authorized?(m)

    add_ignore_sets(m, job, params[:ignore_sets] || [])

    super
  end
end
