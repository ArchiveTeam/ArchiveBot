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

    classes.pushObject('completed') if @get('completed')
    classes.pushObject('aborted') if @get('aborted')

    classes
  ).property('aborted', 'completed')

  queuedAtForDisplay: (->
    stored = (@get('queued_at') || 0) * 1000

    moment.utc(stored).local().fromNow()
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

      @get('content').addLogEntry [entry]

# vim:ts=2:sw=2:et:tw=78
