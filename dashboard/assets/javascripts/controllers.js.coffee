Dashboard.IndexController = Ember.Controller.extend
  needs: ['jobs']

  jobsBinding: 'controllers.jobs'

Dashboard.JobsController = Ember.ArrayController.extend
  itemController: 'job'

Dashboard.HistoryController = Ember.ArrayController.extend
  itemController: 'historyRecord'

  hideHistoryLink: true

  urlBinding: 'content.url'
  urlForDisplayBinding: 'url'

Dashboard.HistoryRecordController = Ember.ObjectController.extend
  classNames: (->
    classes = []

    classes.pushObject('aborted') if @get('aborted')
    classes.pushObject('completed') if @get('completed')

    classes
  ).property('aborted', 'completed')

  queuedAtForDisplay: (->
    # Convert the stored timestamp (which is in UTC) to miliseconds.
    stored = (@get('queued_at') || 0) * 1000

    # Build the date in the browser TZ and let the browser display it.  The
    # default behavior of toLocaleString is pretty complex, but it'll give us
    # year, month, day, hour, minute, and second, which is all we need.  Look
    # up Date on developer.mozilla.org for all the fun details.
    #
    # Important note: When given a value, Date's constructor assumes that it's
    # the number of milliseconds since the start of the UNIX epoch in UTC.  As
    # such, we do not need to convert to local time.
    new Date(stored).toLocaleString()
  ).property('queued_at')

  warcSizeMb: (->
    (@get('warc_size') / (1000 * 1000)).toFixed(2)
  ).property('warc_size')

Dashboard.JobController = Ember.ObjectController.extend
  unregister: ->
    @get('messageProcessor').unregisterJob @get('ident')

  # TODO: If/when Ember.js permits links to be generated on more than model
  # IDs, remove this hack
  historyRoute: (->
    "#/histories/#{@get('url')}"
  ).property('url')

  finishedBinding: 'content.finished'

  okPercentage: (->
    total = @get 'total'
    errored = @get 'error_count'

    100 * ((total - errored) / total)
  ).property('total', 'error_count')

  errorPercentage: (->
    total = @get 'total'
    errored = @get 'error_count'

    100 * (errored / total)
  ).property('total', 'error_count')

  urlForDisplay: (->
    url = @get 'url'

    if url && url.length > 63
      url.slice(0, 61) + '...'
    else
      url
  ).property('url')

  generateCompletionMessage: (->
    if @get('completed')
      @queueSpecialMessage text: 'Job completed', classNames: 'completed'
  ).observes('completed')

  generateAbortMessage: (->
    if @get('aborted')
      @queueSpecialMessage text: 'Job aborted', classNames: 'aborted'
  ).observes('aborted')

  queueSpecialMessage: (params) ->
    Ember.run.next =>
      entry = Ember.Object.create params

      @get('content').addLogEntries [entry]

# vim:ts=2:sw=2:et:tw=78
