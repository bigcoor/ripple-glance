extendNew = require('../utils/routines').extendNew

exports.CunpaiDB = {
  host: 'localhost',
  port: 3306,
  db : ''
  max_conn : 100
  min_conn : 1
  idle_time: 10000
  reap_time: 10000
  refreshIdleBelowMin: false
  name : 'CunpaiDB'
  offset_limit: 6000
  count_limit: 1000
  user: 'cunpai-test'
  passwd: 'AsFLDuqxqg8bX8pnQKRt32eJ'
}
exports.ActivityDB = extendNew({ db: 'activities-test' }, exports.CunpaiDB)
exports.FollowDB = extendNew({ db: 'users-test' }, exports.CunpaiDB)
exports.UserDB = extendNew({ db: 'users-test' }, exports.CunpaiDB)
exports.PasswordDB = extendNew({ db: 'users-test', maxTime: 0.1 }, exports.CunpaiDB)

exports.Common = {
  officialSite: 'http://test.cunpai.com'
}
exports.Logging = {
  currentLevel: 'ERROR',
  categoryLevel: {
    'ACCOUNT': 'ERROR',
    'ACTIVITY': 'ERROR',
    'ACTIVITYSTREAM': 'ERROR',
    'CHOPLET': 'ERROR',
    'CREDENTIALS': 'ERROR',
    'ENTITY': 'ERROR',
    'FOLLOW': 'ERROR',
    'FORMAT': 'ERROR',
    'FRIEND': 'ERROR',
    'GENERIC-POOL_CunpaiDB': 'ERROR',
    'HTTP': 'ERROR',
    'INTRANET': 'ERROR',
    'MEMBERSHIP': 'ERROR',
    'MYSQL': 'ERROR',
    'MYSQL-POOL_CunpaiDB': 'ERROR',
    'NOTIFICATION': 'ERROR',
    'OAUTH': 'ERROR',
    'PROFILE': 'ERROR',
    'QINIU-CALLBACK': 'ERROR',
    'STICKERLET': 'ERROR',
    'TIMELINE': 'ERROR',
    'TRANSACTION': 'ERROR',
    'USER': 'ERROR',
    'UPLOAD': 'ERROR',
    'WALLET': 'ERROR'
  }
}
exports.Token = {
# 用于生成登录token的密钥
# Just a long random string
  tokenKey: 'LPFeRpJox1zovyWTprTQjYzG/JG2JYsGfZ0UVaq+3rs'
}
exports.Web = {
  friendlyJson: true
}
exports.Entity = {
  # 默认水印
  defaultSticker: "1272354511058370560"
}
exports.Format = {
  baseUrlPhoto: 'cunpai-pic-test.u.qiniudn.com',
  baseUrlAvatar: 'cunpai-icon-test.u.qiniudn.com',
  baseUrlWeb: 'cunpai-web-test.qiniudn.com',
  defaultChopBackgroundWidth: 720,
  defaultChopBackgroundHeight: 252
}
exports.Upload = {
  buckets: {
    pic: 'cunpai-pic-test',
    icon: 'cunpai-icon-test',
    web: 'cunpai-web-test'
  },
  accessKey: 'm4vYRdAqy2NzTjt56iLGBn62Fqu5E-E_iySg4M5t',
  secretKey: 'zmsdnn--i5L6IHVJOvdMD8L-m3QbOG_W6Se_Z5nz',
  callbackScheme: 'http',
  callbackAuthority: 'test.cunpai.com:9529',
  callbackPath: '/qiniu'
}
exports.OAuth = {
  QQ: {
    redirectUrl: 'http://test.cunpai.com/oauth/qq',
    redirectUrlMobile: 'http://test.cunpai.com:8194/oauth/qq/mobile',
    owner_qq: '2736188153'
    clientId: '1101973495'
    clientSecret: '4twFBtmYnf8sbSVv'
  },

  Weibo: {
    ownerWeibo: 'api@cunpai.com',
    redirectUrl: 'http://sns.whalecloud.com/sina2/callback',
    redirectUrlMobile: 'http://sns.whalecloud.com/sina2/callback'
    appKey: '3593900486'
    appSecret: 'be763a17232ab4308c4aaafae6f90210'
  }
}
exports.Search = {
  index: 'lookmook-test',
  settings: {
    host: 'http://localhost:9200',
  }
}
exports.NewsFeed = {
  defaultFollowingUids: [100001]
}
exports.Admin = {
  dummyUsers: {
    100435: 'aaaaaa',
    100436: 'aaaaaa'
  }
}
exports.Email = {
  postmark_api_key: 'fb8275dc-86e4-4ff1-b351-56195e253aea'
  notation: 'postmarkapp.com/api@cunpai.com'
}

exports.MongoDB = {
  mongo: 'mongodb://127.0.0.1:27017/ripple-test'
  options:
    db: { native_parser: true }
  # TODO, 搭建MMS, 监控mongodb， 寻找最适合连接池数
    server: { poolSize: 5 }
  # 就近原则secondary db读取数据
    replset: {rs_name: 'rs', salveOk: true}
#    user: 'yinxiangpai'
#    pass: 'MsGGDT89246629MUERxsthjaqbb'
  # 非mognodb链接配置，只是用于分页限制
  count_limit: 200
}

exports.MiPush = {
  gcm:
    appSecret: '/MD3OM3lYY1Ypd4S3Qx7+g=='
    packageName: 'com.cunpai.droid'
    env: 'api'
  aps:
    appSecret: 'RUXXMDlDc3nthiFv4ptXOg=='
    packageName: 'com.cunpai.Cunpai'
    env: 'sandbox'
}

exports.Redis = {
  hostname: 'localhost'
  port: 6379
  db: 0
}

exports.Admin = {
  postConservator: null #内网开发特殊设置
}