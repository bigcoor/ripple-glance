#TODO 1) coffee lint
#TODO 2) livereload & watch

path = require 'path'

module.exports = (grunt) ->
  grunt.loadNpmTasks 'grunt-contrib-concat'
  grunt.loadNpmTasks 'grunt-contrib-coffee'
  grunt.loadNpmTasks 'grunt-contrib-copy'
  grunt.loadNpmTasks 'grunt-preprocess'
  grunt.loadNpmTasks 'grunt-bower-task'
  grunt.loadNpmTasks 'grunt-shell'
  grunt.loadNpmTasks 'grunt-contrib-uglify'
  grunt.loadNpmTasks 'grunt-webpack'
  grunt.loadNpmTasks 'grunt-contrib-jade'

  appDeps = [
    'deps/js/app.js'
    'deps/js/main.js'
    'deps/js/directives.js'
    'deps/js/localize.js'
    'deps/js/UICtrl.js'
    'deps/js/UIDirective.js'
    'deps/js/UIService.js'
    'deps/js/FormDirective.js'
    'deps/js/FormCtrl.js'
    'deps/js/FormValidation.js'
    'deps/js/TableCtrl.js'
    'deps/js/Task.js'
    'deps/js/ChartCtrl.js'
    'deps/js/ChartDirective.js'
  ]

  uiDeps = [
    'deps/js/angular-bootstrap/ui-bootstrap-tpls.min.js'
    'deps/js/jquery-spinner/dist/jquery.spinner.min.js'
    'deps/js/seiyria-bootstrap-slider/dist/bootstrap-slider.min.js'
    'deps/js/jquery-steps/build/jquery.steps.min.js'
    'deps/js/toastr/toastr.min.js'
    'deps/js/bootstrap-file-input/bootstrap.file-input.js'
    'deps/js/jquery.slimscroll/jquery.slimscroll.min.js'
    'deps/js/holderjs/holder.js'
    'deps/js/raphael/raphael-min.js'
    'deps/js/morris.js/morris.js'
    'deps/js/responsive-tables/responsive-tables.js'
    'deps/js/jquery.sparkline/jquery.sparkline.min.js'
    'deps/js/skycons/skycons.js'
    'deps/js/flot/jquery.flot.js'
    'deps/js/flot/jquery.flot.resize.js'
    'deps/js/flot/jquery.flot.pie.js'
    'deps/js/flot/jquery.flot.stack.js'
    'deps/js/flot.tooltip/js/jquery.flot.tooltip.min.js'
    'deps/js/flot/jquery.flot.time.js'
    'deps/js/gauge.js/dist/gauge.min.js'
    'deps/js/jquery.easy-pie-chart/dist/angular.easypiechart.min.js'
    'deps/js/angular-wizard/dist/angular-wizard.min.js'
    'deps/js/textAngular/dist/textAngular-sanitize.min.js'
    'deps/js/textAngular/dist/textAngular.min.js'
    #TODO fix 版本依赖，暂用ui.js
    'src/composite/ui.js'
  ]

  vendorDeps = [
    'deps/js/jquery/dist/jquery.min.js'
    'deps/js/angular/angular.min.js'
    'deps/js/angular-route/angular-route.min.js'
    'deps/js/angular-animate/angular-animate.min.js'
    'deps/js/underscore/underscore-min.js'
    #source map
    'deps/js/angular/angular.min.js.map'
    'deps/js/jquery/dist/jquery.min.map'
    'deps/js/angular-route/angular-route.min.js.map'
    'deps/js/angular-animate/angular-animate.min.js.map'
    'deps/js/underscore/underscore-min.map'
    #TODO fix 版本依赖，vendor.js
    'src/composite/vendor.js'
  ]

  styleDeps = [
    'deps/js/font-awesome/css/font-awesome.min.css'
    'deps/js/weather-icons/css/weather-icons.min.css'
  ]

  # Add a prefix to a filename or array of filenames.
  prefix =(pre, f) ->
    if Array.isArray(f)
      return f.map prefix.bind(this, pre)
    else if 'string' == typeof f
      return pre + f
    else
      return f

  grunt.initConfig
    pkg: grunt.file.readJSON('package.json')

    shell:
      options:
        stdout: true,
        failOnError: true

      startDevServer:
        command:
          if process.platform == 'darwin' then 'coffee ./scripts/web-server.coffee' else 'coffee ./scripts/web-server.coffee'
      clear:
        command: "rm -rf ./build"

    coffee:
      glob_to_multiple:
        expand: true
        flatten: true
        cwd: 'src/client/scripts/'
        src: ['*.coffee']
        dest: 'build/deps/js/app'
        ext: '.js'

    jade:
      compile:
        options:
          data:
            debug: false
        files: [{
          expand: true
          src: "**/*.jade"
          dest: "build/web/views"
          cwd: "src/views"
          ext: '.html'
        }]

    #TODO watch
    watch: {}

    connect:
      debug:
        options:
          hostname: 'localhost'
          port: 8005
          base: '.'
          open: false
          middleware: (connect, options) ->
            return [connect.static(options.base)]

    bower:
      install:
        options:
          install: true
          cleanTargetDir: true
          copy: true
          verbose: true
          targetDir: 'deps/js'

    concat:
      app:
        src: 'build/deps/js/app/*.js'
        dest: "build/web/js/app.js"
      ui:
        src: 'build/deps/js/ui/*.js'
        dest: "build/web/js/ui.js"
      vendor:
        src: 'build/deps/js/vendor/*.js'
        dest: "build/web/js/vendor.js"

    uglify:
      options:
        mangle: false
        sourceMap: false
      app:
        files:
          "build/web/js/app.js": 'build/deps/js/app/*.js'
#TODO tmp
#      ui:
#        files:
#          "build/web/js/ui.js": ['build/deps/js/ui/ui.js']
#      vendor:
#        files:
#          "build/web/js/vendor.js": ['build/deps/js/vendor/vendor.js']

    copy:
      # TODO clear destination folders before copying
      web:
        files: [
          {expand: true, src: appDeps, dest: 'build/deps/js/app/', flatten: true}
          {expand: true, src: uiDeps, dest: 'build/deps/js/ui/', flatten: true}
          {expand: true, src: vendorDeps, dest: 'build/deps/js/vendor/', flatten: true}
          {expand: true, src: styleDeps, dest: 'build/web/styles/', flatten: true}
          {expand: true, cwd: 'deps/js/font-awesome', src: '**', dest: 'build/web/styles/font-awesome'}
          {expand: true, cwd: 'deps/js/weather-icons', src: '**', dest: 'build/web/styles/weather-icons'}
          {expand: true, cwd: 'src/styles', src: '**', dest: 'build/web/styles'}
          {expand: true, cwd: 'src/views', src: '**', dest: 'build/web/views'}
          {expand: true, cwd: 'src/images', src: '**', dest: 'build/web/images'}
          {expand: true, cwd: 'src/fonts', src: '**', dest: 'build/web/fonts'}
          {expand: true, cwd: 'src/i18n', src: '**', dest: 'build/web/i18n'}
          {src: 'src/index.html', dest: 'build/web/index.html'}
        ]

  grunt.registerTask 'default', ['bower:install','shell:clear', 'coffee', 'jade', 'copy', 'deps']

  #Deps only - only rebuilds the dependencies
  #grunt.registerTask 'deps', ['concat:vendor', 'concat:app', 'concat:ui']
  grunt.registerTask 'deps', ['uglify:app']

  #Node.js server to serve built files
  grunt.registerTask 'dev', ['shell:startDevServer']

  #Start server with auto-recompilation
  grunt.registerTask 'serve', ['connect:debug', 'watch']