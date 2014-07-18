# ---------------------------------------------------------------------------
# JOB OUTPUT
# ---------------------------------------------------------------------------

##
# The index page of the dashboard shows a list of job logs.
Dashboard.IndexController = Ember.Controller.extend
  needs: ['jobs']

  dataLoaded: false

  messageProcessorBinding: 'controllers.jobs.messageProcessor'
  selectedSortPropertyBinding: 'controllers.jobs.selectedSortProperty'

  startLogSocket: ->
    @ws = new WebSocket('ws://' + window.location.host + '/stream')

    @ws.onmessage = (msg) =>
      @get('messageProcessor').process(msg.data)

  stopLogSocket: ->
    @ws?.close()

  filteredJobs: (->
    fv = @get('filterValue')

    if !fv
      @get('controllers.jobs')
    else
      @get('controllers.jobs').filter (item, index, controller) ->
        url = item.get('url')
        ident = item.get('ident')

        url.indexOf(fv) != -1 || ident.indexOf(fv) != -1
  ).property('filterValue', 'controllers.jobs.arrangedContent.@each')

jobSorts = {
  url: {
    name: 'URL'
    properties: ['url']
    ascending: true
  },
  age: {
    name: 'age'
    properties: ['started_at']
    ascending: false
  }
}

jobSortCriteria = ({ label: jobSorts[k]['name'], value: k } for own k of jobSorts)

Dashboard.JobsController = Ember.ArrayController.extend
  itemController: 'job'

  modelBinding: 'messageProcessor.jobs'

  availableSortCriteria: jobSortCriteria

  setSort: (->
    selection = jobSorts[@get('selectedSortProperty')]

    # For some reason, use of @setProperties will give you a sort result whose
    # order is not the requested order.
    @set 'sortProperties', selection.properties
    @set 'sortAscending', selection.ascending
  ).observes('selectedSortProperty')

Dashboard.JobController = Ember.ObjectController.extend
  # TODO: If/when Ember.js permits links to be generated on more than model
  # IDs, remove this hack
  historyRoute: (->
    "#/histories/#{@get('url')}"
  ).property('url')

  finishedBinding: 'content.finished'

  frozenBinding: 'content.frozen'

  currentTimeBinding: 'Dashboard.currentTime'

  messageProcessorBinding: 'parentController.messageProcessor'

  elapsedTimeAsMoment: (->
    started = moment.unix @get('content.started_at')
    current = @get('currentTime')

    moment.duration(current - started)
  ).property('currentTime', 'content.started_at')

  elapsedTime: (->
    @get('elapsedTimeAsMoment').humanize()
  ).property('elapsedTimeAsMoment')

  responseRate: (->
    dur = @get('elapsedTimeAsMoment').asSeconds()
    val = @get('content.totalResponses') / dur

    val.toFixed(2)
  ).property('elapsedTimeAsMoment', 'content.totalResponses')

  freeze: ->
    @get('content').addLogEntry Dashboard.FreezeUpdateEntry.create()
    @set 'frozen', true

  unfreeze: ->
    @set 'frozen', false
    Ember.run.next =>
      @get('content').addLogEntry Dashboard.UnfreezeUpdateEntry.create()

  toggleFreeze: ->
    if @get('frozen')
      @unfreeze()
    else
      @freeze()

  unregister: ->
    @get('messageProcessor').unregisterJob @get('ident')

  urlForDisplay: (->
    url = @get 'url'

    if url && url.length > 63
      url.slice(0, 61) + '...'
    else
      url
  ).property('url')

  generateCompletionMessage: (->
    if @get('finished')
      @queueSpecialMessage text: 'Job finished', classNames: 'finished'
  ).observes('finished')

  queueSpecialMessage: (params) ->
    Ember.run.next =>
      entry = Ember.Object.create params

      @get('content').addLogEntry [entry]

# ---------------------------------------------------------------------------
# HISTORY BROWSING
# ---------------------------------------------------------------------------

Dashboard.HistoryController = Ember.ArrayController.extend
  itemController: 'historyRecord'

  hideHistoryLink: true

  urlBinding: 'content.url'
  urlForDisplayBinding: 'url'

Dashboard.HistoryRecordController = Ember.ObjectController.extend
  classNames: (->
    classes = []

    classes.pushObject('finished') if @get('finished')
    classes.pushObject('aborted') if @get('aborted')

    classes.join(' ')
  ).property('aborted', 'finished')

  queuedAtForDisplay: (->
    stored = (@get('queued_at') || 0) * 1000

    moment.utc(stored).local().fromNow()
  ).property('queued_at')

  warcSizeMb: (->
    (@get('warc_size') / (1000 * 1000)).toFixed(2)
  ).property('warc_size')

  downloads: (->
    for obj in @get('archive_urls')
      Ember.Object.create
        url: obj['archive_url'],
        mbSize: (obj['file_size'] / (1000 * 1000)).toFixed(2),
        host: $.url(obj['archive_url']).attr('host')
  ).property('content.archive_urls')

# vim:ts=2:sw=2:et:tw=78
