Dashboard.JobView = Ember.View.extend
  classNameBindings: ['finished']
  classNames: ['job']
  layoutName: 'job-layout'
  tagName: 'article'

  finishedBinding: 'controller.finished'

  didInsertElement: ->
    @$().on 'transitionend webkitTransitionEnd oTransitionEnd otransitionend', =>
      if @get('finished')
        @remove()
        @get('controller').unregister()

Dashboard.ResponseDistributionView = Ember.View.extend
  tagName: 'div'
  templateName: 'distribution-view'

  didInsertElement: ->
    @recalculateWidths()

  updateWidths: (->
    @recalculateWidths()
  ).observes('item.totalResponses', 'item.responseCountsByBucket')

  recalculateWidths: ->
    total = @get 'item.totalResponses'
    counts = @get 'item.responseCountsByBucket'

    return if total == 0

    for pair in counts
      [bucket, count] = pair
      width = (100 * (count / total)) + '%'

      @$(".#{bucket}").css(width: width)

Dashboard.LogView = Ember.View.extend
  classNames: ['terminal', 'log-view']
  classNameBindings: ['showIgnores']

  templateName: 'log-view'

  tagName: 'section'

  maxSize: 512

  autoScrollBinding: 'job.autoScroll'
  showIgnoresBinding: 'job.showIgnores'

  didInsertElement: ->
    @refreshBuffer()

  onLatestEntriesChange: (->
    if @get('job.latestEntries.length') > 0
      @refreshBuffer()
  ).observes('job.latestEntries.@each', 'maxSize')

  refreshBuffer: ->
    buf = @get 'eventBuffer'
    maxSize = @get 'maxSize'

    if !buf
      @set 'eventBuffer', []
      buf = @get 'eventBuffer'

    buf.pushObjects @get('job.latestEntries')
    @get('job.latestEntries').clear()
    
    if buf.length > maxSize
      overage = buf.length - maxSize
      buf.removeAt 0, overage

    if @get('autoScroll')
      Ember.run.next =>
        container = @$()
        return unless container

        container.scrollTop container.prop('scrollHeight')

# vim:ts=2:sw=2:et:tw=78
