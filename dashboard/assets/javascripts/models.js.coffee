# Response code buckets.
RESPONSE_BUCKETS = ['r1xx', 'r2xx', 'r3xx', 'r4xx', 'r5xx', 'runk']

Calculations = Ember.Mixin.create
  mbDownloaded: (->
    (@get('bytes_downloaded') / (1000 * 1000)).toFixed(2)
  ).property('bytes_downloaded')

  # Sadly, there doesn't seem to be a way to reuse RESPONSE_BUCKETS in the
  # property path set.
  responseCountsByBucket: (->
    RESPONSE_BUCKETS.map (bucket) =>
      [bucket, @bucketCount(bucket)]
  ).property('r1xx', 'r2xx', 'r3xx', 'r4xx', 'r5xx', 'runk')

  totalResponses: (->
    RESPONSE_BUCKETS.reduce(((acc, bucket) =>
      acc + @bucketCount(bucket)
    ), 0)
  ).property('r1xx', 'r2xx', 'r3xx', 'r4xx', 'r5xx', 'runk')

  bucketCount: (bucket) ->
    @get(bucket) || 0

Dashboard.Job = Ember.Object.extend Calculations,
  idBinding: 'ident'

  addLogEntry: (entry) ->
    @set 'latestEntries', [entry]

  finished: (->
    @get('aborted') || @get('completed')
  ).property('aborted', 'completed')

  # Properties directly copied from a JSON representation of this job.
  directCopiedProperties: [
    'url', 'ident', 'aborted', 'completed',
    'error_count', 'bytes_downloaded'
  ].pushObjects(RESPONSE_BUCKETS)

  amplify: (json) ->
    props = {}
    props[key] = json[key] for key in @directCopiedProperties
    @setProperties props

Dashboard.JobHistoryEntry = Ember.Object.extend Calculations

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

Dashboard.StdoutUpdateEntry = Ember.Object.extend
  classNames: []

  textBinding: 'message'

Dashboard.MessageProcessor = Ember.Object.extend
  registerJob: (ident) ->
    job = Dashboard.Job.create autoScroll: true, messageProcessor: this

    @get('jobIndex')[ident] = job
    @get('jobs').unshiftObject job

    job

  unregisterJob: (ident) ->
    job = @get('jobIndex')[ident]

    return unless job?

    index = @get('jobs').indexOf job
    @get('jobs').removeAt(index) if index != -1

    delete @get('jobIndex')[ident]

  process: (data) ->
    json = JSON.parse data

    # Sanity-check the message.
    job_data = json['job_data']
    type = json['type']

    console.log 'Message is malformed (no job_data key)' unless job_data?
    console.log 'Message is malformed (no type identifier)' unless type?

    ident = job_data['ident']
    console.log 'Message is malformed (no ident)' unless ident?

    return unless job_data? && ident? && type?

    # Do we have a job for the identifier?
    # If we don't, register a job and retry processing when the run loop
    # comes around again.
    job = @get('jobIndex')[ident]

    if !job?
      @registerJob ident

      Ember.run.next =>
        @process data

      return

    # OK, we have a job.

    # Read the updated job data.
    job.amplify(job_data)

    # Now, update the log buffer.  This part depends on the message type.
    switch type
      when 'download' then @processDownloadUpdate(json, job)
      when 'stdout' then @processStdoutUpdate(json, job)

  processDownloadUpdate: (json, job) ->
    job.addLogEntry Dashboard.DownloadUpdateEntry.create(json)

  processStdoutUpdate: (json, job) ->
    job.addLogEntry Dashboard.StdoutUpdateEntry.create(json)

# vim:ts=2:sw=2:et:tw=78
