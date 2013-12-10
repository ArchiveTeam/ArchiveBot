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

Dashboard.LogEntryView = Ember.View.extend
  tagName: 'div'

  template: Ember.Handlebars.compile '''
    {{#if view.isDownloadEntry}}
      {{#with view.entry}}
        {{response_code}} {{wget_code}}
        <a {{bind-attr href="url"}}>{{url}}</a>
      {{/with}}
    {{else}}
      {{#if view.isIgnoreEntry}}
        {{#with view.entry}}
          {{pattern}} omits
          <a {{bind-attr href="url"}}>{{url}}</a>
        {{/with}}
      {{else}}
        {{view.entry.text}}
      {{/if}}
    {{/if}}
  '''

  isDownloadEntry: (->
    @get('entry.url') && @get('entry.response_code') && @get('entry.wget_code')
  ).property('entry')

  isIgnoreEntry: (->
    @get('entry.pattern')
  ).property('entry')

Dashboard.LogView = Ember.View.extend
  classNames: ['terminal', 'log-view']
  classNameBindings: ['showIgnores']

  templateName: 'log-view'

  tagName: 'section'

  maxSize: 512

  frozenBinding: 'job.frozen'
  showIgnoresBinding: 'job.showIgnores'

  onLatestEntriesChange: (->
    if @get('frozen')
      @acknowledgeLatestEntries()
    else
      @refreshBuffer() if @get('job.latestEntries.length') > 0
  ).observes('job.latestEntries.@each', 'maxSize')

  acknowledgeLatestEntries: ->
    @get('job.latestEntries').clear()

  refreshBuffer: ->
    buf = @get 'eventBuffer'
    maxSize = @get 'maxSize'

    if !buf
      @set 'eventBuffer', []
      buf = @get 'eventBuffer'

    buf.pushObjects @get('job.latestEntries')
    @acknowledgeLatestEntries()
    
    if buf.length > maxSize
      overage = buf.length - maxSize
      buf.removeAt 0, overage

    Ember.run.next =>
      container = @$()
      return unless container

      container.scrollTop container.prop('scrollHeight')

Dashboard.ToggleFreezeView = Ember.View.extend
  tagName: 'button'

  template: Ember.Handlebars.compile '''
    {{view.title}}
  '''

  title: (->
    if @get('job.frozen')
      'Resume output'
    else
      'Pause output'
  ).property('job.frozen')

  click: ->
    @job.toggleFreeze()

# vim:ts=2:sw=2:et:tw=78
