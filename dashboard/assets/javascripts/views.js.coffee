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

Dashboard.ProportionView = Ember.View.extend
  classNames: ['proportion-view']
  templateName: 'proportion-view'

  tagName: 'div'

  didInsertElement: ->
    @sizeBars()

  onProportionChange: (->
    @sizeBars()
  ).observes('okPercentage', 'errorPercentage')

  sizeBars: ->
    @$('.ok').css { width: @get('okPercentage') + '%' }
    @$('.error').css { width: @get('errorPercentage') + '%' }

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

    for pair in counts
      [bucket, count] = pair
      width = (100 * (count / total)) + '%'

      @$(".#{bucket}").css(width: width)

Dashboard.LogView = Ember.View.extend
  classNames: ['terminal', 'log-view']

  templateName: 'log-view'

  tagName: 'section'

  maxSize: 512

  didInsertElement: ->
    @refreshBuffer()

  onIncomingChange: (->
    @refreshBuffer()
  ).observes('incoming', 'maxSize')

  refreshBuffer: ->
    buf = @get 'eventBuffer'
    maxSize = @get 'maxSize'
    incoming = @get('incoming') || []

    if !buf
      @set 'eventBuffer', []
      buf = @get 'eventBuffer'

    buf.pushObjects incoming
    
    if buf.length > maxSize
      overage = buf.length - maxSize
      buf.removeAt 0, overage

    if @get('autoScroll')
      Ember.run.next =>
        container = @$()
        container.scrollTop container.prop('scrollHeight')

# vim:ts=2:sw=2:et:tw=78
