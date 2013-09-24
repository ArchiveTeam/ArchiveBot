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

      if (url && url.length > 63) {
        return url.slice(0, 61) + '...';
      } else {
        return url;
      }
    }.property('url'),

    generateCompletionMessage: function () {
      var entry;

      if (this.get('completed')) {
        entry = Ember.Object.create({
          text: 'Job completed',
          classNames: 'completed'
        });

        this.addLogEntries([entry]);
      }
    }.observes('completed'),

    generateAbortMessage: function () {
      var entry;

      if (this.get('aborted')) {
        entry = Ember.Object.create({
          text: 'Job aborted',
          classNames: 'aborted'
        });

        this.addLogEntries([entry]);
      }
    }.observes('aborted'),

    addLogEntries: function(entries) {
      this.set('latestEntries', entries);
    },

    finished: function () {
      return this.get('aborted') || this.get('completed');
    }.property('aborted', 'completed')
  });

  Dashboard.DownloadUpdateEntry = Ember.Object.extend({
    classNames: function () {
      var warning = this.get('is_warning'),
          error = this.get('is_error'),
          classes = [];

      if (warning) {
        classes.pushObject('warning');
      }

      if (error) {
        classes.pushObject('error');
      }

      return classes;
    }.property('is_warning', 'is_error'),

    text: function () {
      return [
        this.get('response_code'),
        this.get('wget_code'),
        this.get('url')
      ].join(' ');
    }.property('response_code', 'wget_code', 'url')
  });

  Dashboard.MessageProcessor = Ember.Object.extend({
    registerJob: function(ident) {
      var job = Dashboard.Job.create({autoScroll: true});

      this.jobIndex[ident] = job;
      this.jobs.pushObject(job);

      return job;
    },

    unregisterJob: function (ident) {
      var job = this.jobIndex[ident], index;

      if (!job) {
        return;
      }

      index = this.jobs.indexOf(job);

      if (index !== -1) {
        this.jobs.removeAt(index);
      }

      delete this.jobIndex[ident];
    },

    process: function(data) {
      var json = JSON.parse(data),
          ident = json['ident'],
          type = json['type'],
          job;

      // Does the message have a job identifier?
      if (!ident) {
        console.log("Message is malformed (doesn't have a job identifier)");
        return;
      }

      // Does the message have a type?
      if (!type) {
        console.log("Message is malformed (doesn't have a type)");
        return;
      }
      // Do we have a job for the identifier?
      job = this.jobIndex[ident];

      // If we don't, register a job and retry processing when the run loop
      // comes around again.
      if (!job) {
        this.registerJob(ident);

        Ember.run.next(this, function () {
          this.process(data);
        });

        return;
      }

      // If we do, process the message.
      switch (json['type']) {
        case 'status_change':
          this.processStatusChange(json, job);
          break;
        case 'download_update':
          this.processDownloadUpdate(json, job);
          break;
        default:
          console.log('Cannot handle message type', json['type']);
          break;
      }
    },

    processStatusChange: function(json, job) {
      var ident = json['ident'];

      job.setProperties({
        aborted: json['aborted'],
        completed: json['completed']
      });
    },

    processDownloadUpdate: function(json, job) {
      var ident = json['ident'];

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
        bytes_downloaded: json['bytes_downloaded']
      });

      job.addLogEntries(json['entries'].map(function(item) {
        return Dashboard.DownloadUpdateEntry.create(item);
      }));
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

  Dashboard.JobView = Ember.View.extend({
    classNameBindings: ['finished'],
    classNames: ['job'],

    tagName: 'article',

    hideWhenFinished: function () {
      var that = this;

      // You should make sure that this timeout is at least as long as the sum
      // of the above CSS animation's duration and delay, which currently is
      // 10000ms + 500ms = 10500ms.  A bit of slop is also useful, because
      // browser timeouts are not precise.
      setTimeout(function () {
        that.remove();
        that.get('jobList').unregisterJob(that.get('ident'));
      }, 11000);
    }.observes('finished')
  });

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

    classNames: ['terminal', 'log-view'],

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
