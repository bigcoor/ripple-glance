exports.MaxInt = 4294967295
exports.MaxTimestampMills = 2147485547000
exports.MaxUnixtime = 2147483647

# 请勿修改以下常量，否则将导致数据丢失
exports.albumCreator = 10007
exports.featuredAlbumListCreator = 10008
exports.stickerCreator = 10029
exports.chopCreator = 10030
exports.featuredListCreator = 10033
exports.bagCreator = 10035
exports.topicCreator = 10037
exports.eventAlbumListCreator = 10039
exports.splashAlbumListCreator = 10040
exports.featuredTopicListCreator = 10041
exports.arenaCreator = 10050
exports.blinkCreator = 10101
exports.channelCreator = 10102
exports.salonCreator = 10103

# TODO, 用association重新实现.
# 由于album可完全由后台编辑，所以这里的实现暂时采用relation的方式。
exports.featuredAlbumList = '994576473072774180'
exports.eventAlbumList =    '1124302229164595200'
exports.splashAlbumList =   '1116332333467494912'

#topic
exports.featuredTopicList = '2116442555689610037'

# deprecated
exports.featuredList = '541479857746345984' # this is a non-existent id, can just leave it as it is