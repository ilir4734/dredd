{EventEmitter} = require 'events'
async = require 'async'
fs = require 'fs'
protagonist = require 'protagonist'
executeTransaction = require './execute-transaction'
blueprintAstToRuntime = require './blueprint-ast-to-runtime'
configureReporters = require './configure-reporters'

options =
  'dry-run': {'alias': 'd', 'description': 'Run without performing tests.', 'default': false}
  'silent': {'alias': 's', 'description': 'Suppress all command line output.', 'default': false}
  'reporter': {'alias': 'r', 'description': 'Output additional report format. This option can be used multiple times to add multiple reporters. Options: junit, nyan, dot, markdown, html', default:[]}
  'output': {'alias': 'o', 'description': 'Specifies output file when using additional file-based reporter. This option can be used multiple times if multiple file-based reporters are used.', default: []}
  'header': {'alias': 'h', 'description': 'Extra header to include in every request. This option can be used multiple times to add multiple headers.', default:[]}
  'verbose': { 'description': 'Display debug information', 'default': false}

###
  Events:
  start
  end
  test start
  test fail
  test pass
  test skip
  test error
###

coerceToArray = (value) ->
  if typeof value is 'string'
    value = [value]
  else if !value?
    value = []
  else if value instanceof Array
    value
  else value

class Dredd
  constructor: (config) ->
    emitter = new EventEmitter
    @configuration =
      blueprintPath: null
      server: null
      emitter: emitter
      options:
        'dry-run': false
        silent: false
        reporter: null
        output: null
        debug: false
        header: null
    @testData =
      tests: [],
      stats:
        tests: 0
        failures: 0
        errors: 0
        passes: 0
        skipped: 0
        start: 0
        end: 0
        duration: 0

    #normalize options and config
    for own key, value of config
      @configuration[key] = value

    #coerce single/multiple options into an array
    @configuration.options.reporter = coerceToArray(@configuration.options.reporter)
    @configuration.options.output = coerceToArray(@configuration.options.output)
    @configuration.options.header = coerceToArray(@configuration.options.header)

    configureReporters(@configuration, @testData)

  run: (callback) ->
    config = @configuration
    stats = @testData.stats

    config.emitter.emit 'start'

    fs.readFile config.blueprintPath, 'utf8', (parseError, data) ->
      return callback(parseError, config.reporter) if parseError

      protagonist.parse data, (protagonistError, result) ->
        return callback(protagonistError, config.reporter) if protagonistError

        runtime = blueprintAstToRuntime result['ast']

        runtimeError = handleRuntimeProblems runtime
        return callback(runtimeError, config.reporter) if runtimeError

        async.eachSeries configuredTransactions(runtime, config), executeTransaction, (error) ->
          if error
            config.emitter 'test error', error

          config.emitter.emit 'end'
          # don't callback to give reporters time to clean up
          #callback(null, stats)

  handleRuntimeProblems = (runtime) ->
    if runtime['warnings'].length > 0
      for warning in runtime['warnings']
        message = warning['message']
        origin = warning['origin']

        cli.info "Runtime compilation warning: " + warning['message'] + "\n on " + \
          origin['resourceGroupName'] + \
          ' > ' + origin['resourceName'] + \
          ' > ' + origin['actionName']

    if runtime['errors'].length > 0
      for error in runtime['errors']
        message = error['message']
        origin = error['origin']

        cli.error "Runtime compilation error: " + error['message'] + "\n on " + \
          origin['resourceGroupName'] + \
          ' > ' + origin['resourceName'] + \
          ' > ' + origin['actionName']

      return new Error "Error parsing ast to blueprint."

  configuredTransactions = (runtime, config) ->
    transactionsWithConfiguration = []

    for transaction in runtime['transactions']
      transaction['configuration'] = config
      transactionsWithConfiguration.push transaction

    return transactionsWithConfiguration



module.exports = Dredd
module.exports.options = options