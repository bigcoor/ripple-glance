async = require 'async'

profile = require './controllers/profile'
account = require './features/account'
auth = require './features/auth'
captchalib = require './features/captcha'
checker = require './features/checker'

renderNotImplemented = (req, res) ->
  res.send(501)

denyAccess = (res) ->
  res.setHeader('WWW-Authenticate', 'Credentials realm="lookmook.cn"')
  res.send(401)

module.exports = (app) ->
  # 注册新用户
  app.post('/accounts/users', (req, res) ->
    body = req.body
    captcha = req.body.captcha ? ''
    captchaToken = req.body.token
    context = {}

    async.waterfall([
      # TODO, add captcha
      #async.apply(auth.validateCaptchaToken, captcha, captchaToken),
      async.apply(account.register, body, context)
    ], (err, result) ->
      if err?
        if err.nothuman
          res.send(402) # Payment Required, like YouTube
        else if err.duplicate
          res.send(409)
        else if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 用户登陆
  # POST /auth/sessions
  # Content-Type application/json
  # Body { email: 'xxxx', nick: 'xxxx', password: 'xxxxxxx' }
  # Query String idle: session timeout in seconds (defaults to 30 minutes)
  # Query String persist: remember me token, expiration in minutes (defaults to 30 days)
  # Header uid: xxxxxxxx
  # Header persist: xxxxxxxxxxx # remember me token
  # Response { uid: xxxxx, sessionToken: 'xxxxxxxx', persistToken: 'xxxxxxxxx' }
  # Sample 1 Use Password: curl -H 'Content-Type: application/json' -d '{"email":"jun@cunpai.com","password":"xxxxxxxxxx"}' majun.homeserver.com:16384/auth/sessions?idle=1200&persist=20160
  # Sample 2 Use Remember Me Token: curl -H 'Content-Type: application/json' -H 'uid: 100000' -H 'persist: xxxxxxx' -d '{}' majun.homeserver.com:16384/auth/sessions?idle=1200&persist=20160
  app.post('/auth/sessions', (req, res) ->
    email = req.body.email
    phone = req.body.phone
    password = req.body.password
    captcha = req.body.captcha ? ''
    captchaToken = req.body.token

    if phone?
      signIn = auth.phoneSignIn
      handle = phone
    else if email?
      signIn = auth.emailSignIn
      handle = email

    uid = req.header('uid')
    token = req.header('persist')

    usePassword = signIn and password
    useToken = uid and token

    if not usePassword and not useToken
      res.send(400)
      return

    if usePassword
      async.waterfall([
          # TODO, captcha
          #async.apply(auth.validateCaptchaToken, captcha, captchaToken),
          async.apply(signIn, handle, password, req.query.idle, req.query.persist)
        ], (err, result) ->
        if err?
          if err.nothuman
            res.send(402) # Payment Required, like YouTube
          else
            res.send(500)
        else if not result
          denyAccess(res)
        else
          res.json(result)
      )
    else if useToken
      auth.acquireSession(uid, token, req.query.idle, req.query.persist, (err, result) ->
        if err?
          denyAccess(res)
        else
          res.json(result)
      )
  )

  # 用于OAuth Authorization_Code方式的回调函数
  app.post('/oauth/qq', (req, res) ->
    code = req.query.code
    state = req.query.state

    if not code or not state
      return res.send(400)

    auth.qqSignIn(req.header('uid'), code, false, req.query.idle, req.query.persist, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    )
  )

  # 找回密码
  #
  # 402，token错误
  # 404，邮箱不存在
  # 500，内部错误，例如邮件发送失败等
  # 400, 请求格式错误
  app.put('/accounts/passwords/find', (req, res) ->
    body = req.body
    captcha = body.captcha ? ''
    captchaToken = body.token

    async.waterfall([
        async.apply(auth.validateCaptchaToken, captcha, captchaToken),
        async.apply(account.findPassword, body.email)
      ], (err, result) ->
      if err?
        if err.nothuman
          res.send(402)
        if err.notfound
          res.send(404)
        if err.badRequest
          res.send(400)
        else
          res.send(500)
      else
        res.json(result)
    )
  )

  app.get('/accounts/availability', (req, res) ->
    cb = (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json(result)
    if req.query.nick
      checker.nicknameAvailable(req.query.nick, cb)
    else if req.query.email
      checker.emailAvailable(req.query.email, cb)
    else
      res.send(400)
  )

  app.get('/captcha', (req, res) ->
    async.parallel({
        token: async.apply(auth.generateCaptchaToken, '', 60),
        captcha: async.apply(captchalib, '')
      }, (err, result) ->
      if err?
        if err.tryagain
          res.send(500)
        else
          res.send(400)
      else
        res.json({
          protocol: 1.0,
          token: result.token,
          captcha: result.captcha.toString('base64')
        })
    )
  )