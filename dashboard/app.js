(function () {
  "use strict";

  window.Dashboard = Ember.Application.create();

  // -------------------------------------------------------------------------
  // MODELS
  // ------------------------------------------------------------------------- 
  Dashboard.Job = Ember.Object.extend({
    okPercentage: function () {
      var total = this.get('total'),
          errored = this.get('error_count'),
          pct = 100.0 * ((total - errored) / total);

      return pct;
    }.property('total', 'error_count'),

    errorPercentage: function () {
      var total = this.get('total'),
          errored = this.get('error_count'),
          pct = 100.0 * (errored / total);

      return pct;
    }.property('total', 'error_count'),

    mibDownloaded: function () {
      return (this.get('bytes_downloaded') / (1024 * 1024)).toFixed(2);
    }.property('bytes_downloaded'),

    urlForDisplay: function () {
      var url = this.get('url');

      if (url.length > 63) {
        return url.slice(0, 61) + '...';
      } else {
        return url;
      }
    }.property('url')
  });

  Dashboard.LogEntry = Ember.Object.extend({
  });

  Dashboard.MessageProcessor = Ember.Object.extend({
    process: function(data) {
      var json = JSON.parse(data),
          ident = json['ident'],
          job = this.jobIndex[ident];

      if (job === undefined) {
        job = Dashboard.Job.create({autoScroll: true});
  
        this.jobIndex[ident] = job;
        this.jobs.pushObject(job);
      }

      job.setProperties({
        url: json['url'],
        ident: json['ident'],
        r1xx: json['r1xx'],
        r2xx: json['r2xx'],
        r3xx: json['r3xx'],
        r4xx: json['r4xx'],
        r5xx: json['r5xx'],
        runk: json['runk'],
        total: json['total'],
        error_count: json['error_count'],
        bytes_downloaded: json['bytes_downloaded'],
        latestEntries: json['entries'].map(function (item) {
          return Dashboard.LogEntry.create(item);
        })
      });
    }
  });

  var messageProcessor = Dashboard.MessageProcessor.create({
    jobIndex: {},
    jobs: Ember.A([])
  });

  Dashboard.messageProcessor = messageProcessor;

  // -------------------------------------------------------------------------
  // ROUTES
  // -------------------------------------------------------------------------

  Dashboard.IndexRoute = Ember.Route.extend({
    model: function () {
      return messageProcessor;
    }
  });

  // -------------------------------------------------------------------------
  // CONTROLLERS
  // -------------------------------------------------------------------------

  Dashboard.IndexController = Ember.Controller.extend({
    needs: ['processor'],

    jobsBinding: 'controllers.processor.content'
  });

  Dashboard.ProcessorController = Ember.ArrayController.extend({
    content: messageProcessor.get('jobs')
  });

  // -------------------------------------------------------------------------
  // VIEWS
  // -------------------------------------------------------------------------

  Dashboard.ProportionView = Ember.View.extend({
    templateName: 'proportion-view',

    tagName: 'div',

    classNames: ['success-bar'],

    didInsertElement: function () {
      this.sizeBars();
    },

    onProportionChange: function () {
      this.sizeBars();
    }.observes('okPercentage', 'errorPercentage'),

    sizeBars: function () {
      this.$('.ok').css({width: this.get('okPercentage') + '%'});
      this.$('.error').css({width: this.get('errorPercentage') + '%'});
    }
  });

  Dashboard.LogView = Ember.View.extend({
    templateName: 'log-view',

    tagName: 'section',

    classNames: ['terminal'],

    maxSize: 512,

    didInsertElement: function () {
      this.refreshBuffer();
    },

    onIncomingChange: function () {
      this.refreshBuffer();
    }.observes('incoming', 'maxSize'),

    refreshBuffer: function () {
      var buf = this.get('eventBuffer'),
          maxSize = this.get('maxSize'),
          incoming = this.get('incoming') || [],
          overage;

      if (!buf) {
        this.set('eventBuffer', []);
        buf = this.get('eventBuffer');
      }

      buf.pushObjects(incoming);

      if (buf.length > maxSize) {
        overage = buf.length - maxSize;
        buf.removeAt(0, overage);
      }

      if (this.get('autoScroll')) {
        Ember.run.next(this, function () {
          var container = this.$();

          container.scrollTop(container.prop('scrollHeight'));
        });
      }
    }
  });
})();

// vim:ts=2:sw=2:et:tw=78
