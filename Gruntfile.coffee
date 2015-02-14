#TODO 1) coffee lint
#TODO 2) livereload & watch

path = require 'path'

module.exports = (grunt) ->
  grunt.loadNpmTasks 'grunt-contrib-coffee'
  grunt.loadNpmTasks 'grunt-contrib-copy'
  grunt.loadNpmTasks 'grunt-bower-task'
  grunt.loadNpmTasks 'grunt-shell'
  grunt.loadNpmTasks 'grunt-contrib-uglify'
  grunt.loadNpmTasks 'grunt-webpack'
  grunt.loadNpmTasks 'grunt-contrib-jade'
  grunt.loadNpmTasks('grunt-contrib-clean')

  styleDeps = [
    'deps/js/font-awesome/css/font-awesome.min.css'
    'deps/js/weather-icons/css/weather-icons.min.css'
  ]

  webpack =
    options:
      module:
        preLoaders: [
          {
            test: /\.coffee$/
            include: pathToRegExp(path.join(__dirname, 'src', 'client'))
            loader: 'coffee-loader'
          }
        ]
      output:
        filename: "build/deps/coffee/"
    webDebug:
    #fix require fs
      node: {
        fs: "empty"
      }
    #fix require json file
      module:
        loaders: [
          {test: /\.json$/, loader: "json"}
          {test: /\.jade$/, loader: "jade"}
        ]

      modulesDirectories: ["web_loaders", "web_modules", "node_loaders", "node_modules"]
      entry:
        web: "./src/client/entry/app.coffee"
      output:
        filename: "build/deps/js/app/app.js"
      devtool: 'eval',
      debug: true

  grunt.initConfig
    pkg: grunt.file.readJSON('package.json')

    shell:
      options:
        stdout: true,
        failOnError: true

      startDevServer:
        command:
          'NODE_ENV=dev coffee ./scripts/web-server.coffee'

      startProdServer:
        command:
          'NODE_ENV=prod coffee ./scripts/web-server.coffee'

      clear:
        command: "rm -rf ./build"

  #TODO Tmp
    coffee:
      glob_to_multiple:
        expand: true
        flatten: true
        cwd: 'src/client/'
        src: ['**/*.coffee']
        dest: 'build/deps/js/app'
        ext: '.js'

    jade:
      compile:
        options:
          data:
            debug: true
        files: [
          {
            expand: true
            src: "**/*.jade"
            dest: "build/web/views"
            cwd: "src/views"
            ext: '.html'
          }
          {
            expand: true
            src: 'index.jade'
            cwd: "src"
            dest: 'build/web'
            ext: '.html'
          }
        ]

  #TODO watch
    watch: {}

    bower:
      install:
        options:
          install: true
          cleanTargetDir: true
          copy: true
          verbose: true
          targetDir: 'src/javascript'

    uglify:
      options:
        mangle: false
        sourceMap: false
      app:
        files:
          "build/web/js/app.js": 'build/deps/js/app/*.js'
    #TODO tmp
      ui:
        files:
          "build/web/js/ui.js": ['src/composite/ui.js']
      vendor:
        files:
          "build/web/js/vendor.js": ['src/composite/vendor.js']

    copy:
    # TODO clear destination folders before copying
      web:
        files: [
          {expand: true, src: styleDeps, dest: 'build/web/styles/', flatten: true}
          {expand: true, cwd: 'src/javascript/font-awesome', src: '**', dest: 'build/web/styles/font-awesome'}
          {expand: true, cwd: 'src/javascript/weather-icons', src: '**', dest: 'build/web/styles/weather-icons'}
          {expand: true, cwd: 'src/styles', src: '**', dest: 'build/web/styles'}
          {expand: true, cwd: 'src/images', src: '**', dest: 'build/web/images'}
          {expand: true, cwd: 'src/fonts', src: '**', dest: 'build/web/fonts'}
          {expand: true, cwd: 'src/i18n', src: '**', dest: 'build/web/i18n'}
        ]
      server:
        files: [
          {expand: true, cwd: 'src/server', src: '**', dest: 'build/server/'}
        ]

    clean:
      folders: ['build/deps']

  grunt.config.set('webpack', webpack)

  grunt.registerTask 'default', ['bower:install','shell:clear', 'coffee', 'jade', 'copy', 'deps']

  #Deps only - only rebuilds the dependencies
  #grunt.registerTask 'deps', ['concat:vendor', 'concat:app', 'concat:ui']
  grunt.registerTask 'deps', ['uglify:app', 'uglify:ui', 'uglify:vendor']

  #Node.js server to serve built files
  grunt.registerTask 'web', ['shell:clear', 'jade', 'copy', 'webpack:webDebug', 'deps', 'clean:folders', 'shell:startDevServer']

  grunt.registerTask 'server', ['copy:server', 'shell:startDevServer']

  #Deploy Production
  grunt.registerTask 'deploy', ['shell:clear', 'jade', 'copy', 'webpack:webDebug', 'deps', 'clean:folders', 'shell:startProdServer']

#Helpers
escapeRegExpString = (str) -> return str.replace(/[\-\[\]\/\{\}\(\)\*\+\?\.\\\^\$\|]/g, '\\$&')
pathToRegExp = (p) -> return new RegExp('^' + escapeRegExpString(p))