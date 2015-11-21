module AddIgnoreSets
  def run_post_registration_hooks(m, job, params)
    add_ignore_sets(m, job, params[:ignore_sets] || [], false)

    super
  end
end
