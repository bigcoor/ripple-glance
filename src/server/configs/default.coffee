exports.PORT = 3000
extendNew = require('../utils/routines').extendNew

exports.Logging = {
  currentLevel: 'ERROR'
}
exports.Timed = {
  defaultTimeout: 2000
}
exports.Token = {
  tokenKey: '<your token here>' # Just a long random string
}
exports.UniqueID = {
  machineId: 0
}
exports.AppID = {
  cunpai: 1
}
exports.Pagination = {
  defaultPageSize: 20,
  maxPageSize: 100,
# 最大偏移量，即最多可以获取几项
  maxOffset: Infinity
}
exports.NewsFeed = {
  filter: [1],
  limit: 1000,
  dynamics: [1, 2],
  activityLog: [1, 2, 3, 4, 7],
# 列表中用户的post将会默认出现在所有人的关注列表中
  defaultFollowingUids: []
}
exports.Format = {
  defaultIcon: 'default-icon',
  defaultChopLogo: 'default-chop-logo',
  defaultChopBackground: 'default-chop-bg',
  historyArenaCover: 'history-event-cover',

  baseUrlPhoto: '<photo-bucket>',
  baseUrlAvatar: '<avatar-bucket>',
  baseUrlWeb: '<web-bucket>',
  stylePhoto: {
    raw: '',
    display: '/display',
    display_large: '/large',
    thumb: '/thumb'
  },
  styleAvatar: {
    avatar: '/avatar',
    square: '/square'
  },
  styleWeb: {},
# 品牌的logo
  styleChopLogo: {
  }
# 移动终端屏幕常见宽度， 必须从小到大排序
  baseWidth: [240, 360, 480, 540, 640, 720, 1080, 1152, 1242, 1536]
}
exports.Upload = {
  lifetime: 300,
  buckets: {
    pic: '<bucket-name>',
    icon: '<bucket-name>',
    web: '<bucket-name>'
  },
  styles: {
    pic: 'imageView2/1/w/240/h/240/q/100/format/JPG;
          imageView2/1/w/360/h/360/q/100/format/JPG;
          imageView2/1/w/480/h/480/q/100/format/JPG;
          imageView2/1/w/540/h/540/q/100/format/JPG;
          imageView2/1/w/640/h/640/q/100/format/JPG;
          imageView2/1/w/720/h/720/q/100/format/JPG;
          imageView2/2/w/1080/h/1080/q/100/format/JPG;
          imageView2/1/w/1152/h/1152/q/100/format/JPG;
          imageView2/1/w/1242/h/1242/q/100/format/JPG;
          imageView2/1/w/1536/h/1536/q/100/format/JPG;'
    icon: 'imageView2/1/w/180/q/100/format/PNG;imageView2/1/w/50/q/100/format/PNG',
  # TODO, web不需要预处理
    web: ''
  },
  previews: {
    pic: 'previewPhoto',
    icon: 'previewAvatar',
    web: 'previewWeb'
  },
  accessKey: '<qiniu-access-key>',
  secretKey: '<qiniu-access-secret>',
  callbackScheme: 'http',
  callbackAuthority: '<qiniu-callback>',
  callbackPath: '/qiniu',
  callbackParams: 'uid=$(endUser)&name=$(fname)&hash=$(etag)&size=$(fsize)&mime=$(mimeType)&info=$(imageInfo)&exif=$(exif)&quiet=$(x:silence)&bucket=$(bucket)&key=$(key)',
  sizeLimit: 10485760,
  mimeLimit: 'image/*;application/zip'
}
exports['Wall-E'] = {
  count: 10,
  concurrency: 1
}
exports.Notification = {
  summaryFilter: [2, 4, 8, 12, 13, 15, 16, 19, 27, 28, 33, 34],
  summaryLimit: 100,
  typeLimit: 1000
}
exports.Web = {
  sizeLimit: '8kb'
# 格式化返回的JSON
  friendlyJson: false
}
exports.Load = {
  pendingThreshold: 10000,
  responseTimeout: 3000,
  queueTimeout: 2000
}
exports.Checker = {
  minNickAsciiLength: 3,
  maxNickCharLength: 14, # 24 is the db limit
  minDescLength: 1,
  maxDescLength: 3584
}
exports.Profile = {
  defaultPublicFields: { },
  defaultIntroductions: [
    '时尚不跟风，我的个性自成一派'
  ]
}
exports.Profile.defaultPublicFields[exports.AppID.cunpai] = {
  introduction: true
}
exports.Membership = {
  limit: 1000,
  latest: {
    activity: extendNew([{ var: 'type', val: 1 }, { var: 'count', min: 1 }], { rel: 'AND' }),
    follow: null
  }
}
exports.Http = {
  maxSockets: 10
}
exports.OAuth = {
  QQ: {
    urls: {
      authorizeUrl: 'https://graph.qq.com/oauth2.0/authorize'
      tokenUrl: 'https://graph.qq.com/oauth2.0/token'
      openIdUrl: 'https://graph.qq.com/oauth2.0/me'
      baseUrl: 'https://graph.qq.com/user'
    }
  },

  Weibo: {
    urls: {
      authorizeUrl: 'https://api.weibo.com/oauth2'
      baseUrl: 'https://api.weibo.com'
    }
  }
}
exports.Entity = {
  brandCreator: 10000,
  modelCreator: 10000,
  commdityCreator: 10000,
  campaignCreator: 10001,
  inventoryCreator: 10001,
  posterCreator: 10001,
# TODO, change to 10034
  reviewer: 10006

  quote_text : [
    "那些冒险的梦，我陪你去疯",
    "在最深的绝望里，遇见最美的意外",
    "只要未来有你，面对一切，我无所畏惧",
    "请相信，你是发生在我身上最好的事情",
    "宠爱自己，才是最重要的事",
    "我就是我，是颜色不一样的烟火",
    "人生总会有不期而遇的风景",
    "沿途多彩的风景，渲染潮湿的心",
    "风华如一指流沙，苍老如一段年华",
    "我的世界只有我一个人已经足够热闹",
    "有时，单身反而是一种自信和诚实",
    "注定，有些路，只能一个人走",
    "生命匆匆，何必委曲求全",
    "人生如此短暂，不穿漂亮点怎么行",
    "Always simple, not redundant",
    "用一杯水的单纯，面对一辈子的复杂",
    "最美的不是下雨天，是与你躲过雨的屋檐",
    "走遍世界才发现，笑容才是最美的风景"
  ]
}
exports.Device = {
  allDeviceUser: 10003
}
exports.Wallet = {
  minAmountPerWithdraw: 20,
  maxAmountPerWithdraw: 200,
  maxAmountWithinPeriod: 1000,
  amountLimitPeriod: 24 # hours
  maxTimesWithinPeriod: 3,
  timeLimitPeriod: 24, # hours
  paymentOperator: 10004
}
exports.Feedback = {
  feedbackOperator: 10005,
  anonymousUser: 20000
}
exports.Search = {
  index: '<index-name>',
  settings: {
    host: '<service-host>',
    maxRetries: 3,
    keepAlive: true,
    maxSockets: 50,
    minSockets: 10
  }
}
exports.Message = {
  welcome: '欢迎来到lookmook，在这里，漂亮的水印让本来就很美的你变身为封面模特，还能发现一样Style的姐妹们'
  shareContent: '欢迎来到lookmook，在这里，漂亮的水印让本来就很美的你变身为封面模特，还能发现一样Style的姐妹们'
}

exports.Approach = {
  boolFilter: false #开启渠道内容过滤
  versionExclude: []#过滤版本列表
}

exports.OfficialId = {
  admin: 100002
  lookmooker: [100002, 100082]
}

exports.Channel = {
  defaultId: "54cb024a7081de6e69df1628"
  defaultUser: null
}

exports.Salon = {
  givenIdList: ["54d4728afce4902329310308", "54d9dc88dc34516737898cc5"]
}

