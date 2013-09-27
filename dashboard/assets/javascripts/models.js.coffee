Calculations = Ember.Mixin.create
  mbDownloaded: (->
    (@get('bytes_downloaded') / (1000 * 1000)).toFixed(2)
  ).property('bytes_downloaded')

# Response code buckets.
RESPONSE_BUCKETS = ['r1xx', 'r2xx', 'r3xx', 'r4xx', 'r5xx', 'runk']

Dashboard.Job = Ember.Object.extend Calculations,
  idBinding: 'ident'

  addLogEntries: (entries) ->
    @set 'latestEntries', entries

  finished: (->
    @get('aborted') || @get('completed')
  ).property('aborted', 'completed')

  # Properties directly copied from a JSON representation of this job.
  #
  # See amplify.
  directCopiedProperties: [
    'url', 'ident',
    'total', 'error_count',
    'bytes_downloaded'
  ].pushObjects(RESPONSE_BUCKETS)

  amplify: (json) ->
    props = {}
    props[key] = json[key] for key in @directCopiedProperties
    @setProperties props

Dashboard.JobHistoryEntry = Ember.Object.extend Calculations,
  totalResponses: (->
    RESPONSE_BUCKETS.reduce(((acc, bucket) =>
      acc + @get(bucket)
    ), 0)
  ).property(RESPONSE_BUCKETS)

  responseCountsByBucket: (->
    RESPONSE_BUCKETS.map (bucket) =>
      [bucket, @get(bucket)]
  ).property(RESPONSE_BUCKETS)

Dashboard.DownloadUpdateEntry = Ember.Object.extend
  classNames: (->
    classes = []

    classes.pushObject('warning') if @get('is_warning')
    classes.pushObject('error') if @get('is_error')

    classes
  ).property('is_warning', 'is_error')

  text: (->
    [@get('response_code'), @get('wget_code'), @get('url')].join(' ')
  ).property('response_code', 'wget_code', 'url')

Dashboard.MessageProcessor = Ember.Object.extend
  registerJob: (ident) ->
    job = Dashboard.Job.create autoScroll: true, messageProcessor: this

    @get('jobIndex')[ident] = job
    @get('jobs').pushObject job

    job

  unregisterJob: (ident) ->
    job = @get('jobIndex')[ident]

    return unless job?

    index = @get('jobs').indexOf job
    @get('jobs').removeAt(index) if index != -1

    delete @get('jobIndex')[ident]

  process: (data) ->
    json = JSON.parse data
    ident = json['ident']
    type = json['type']

    # Sanity-check the message.
    console.log 'Message is malformed (no ident)' unless ident?
    console.log 'Message is malformed (no type identifier)' unless type?

    # Do we have a job for the identifier?
    # If we don't, register a job and retry processing when the run loop
    # comes around again.
    job = @get('jobIndex')[ident]

    if !job?
      @registerJob ident

      Ember.run.next =>
        @process data

      return

    # If we do, process the message.
    switch json['type']
      when 'status_change' then @processStatusChange(json, job)
      when 'download_update' then @processDownloadUpdate(json, job)
      else console.log "Can't handle message type #{json['type']}"

  processStatusChange: (json, job) ->
    job.setProperties
      aborted: json['aborted']
      completed: json['completed']

  processDownloadUpdate: (json, job) ->
    job.amplify(json)

    job.addLogEntries(json['entries'].map (item) ->
      Dashboard.DownloadUpdateEntry.create(item)
    )


# vim:ts=2:sw=2:et:tw=78
