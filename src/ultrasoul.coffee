# Description
#   Add reaction to ultrasoul messages
#
# Configuration:
#   HUBOT_SLACK_ULTRASOUL_MECAB_API_URL - set mecab-api URL
#   HUBOT_SLACK_ULTRASOUL_REACTION      - set reaction emoji (default. raising_hand)
#
# Reference
#   https://github.com/hakatashi/slack-ikku
#
# Author:
#   knjcode <knjcode@gmail.com>

{Promise} = require 'es6-promise'

max = require 'lodash.max'
reduce = require 'lodash.reduce'
tokenize = require 'kuromojin'
unorm = require 'unorm'
util = require 'util'
zipWith = require 'lodash.zipwith'

mecabUrl = process.env.HUBOT_SLACK_ULTRASOUL_MECAB_API_URL
if !mecabUrl
  console.error("ERROR: You should set HUBOT_SLACK_ULTRASOUL_MECAB_API_URL env variables.")

reaction = process.env.HUBOT_SLACK_ULTRASOUL_REACTION ? 'raising_hand'

module.exports = (robot) ->
  checkArrayDifference = (a, b) ->
    tmp = zipWith a, b, (x, y) ->
      x - y
    .map (x) -> max [x, 0]
    reduce tmp, (sum, n) -> sum + n

  addReaction = (reaction, msg) -> new Promise (resolve) ->
    channelId = robot.adapter.client.getChannelGroupOrDMByName(msg.envelope.room)?.id
    robot.adapter.client._apiCall 'reactions.add',
      name: reaction
      channel: channelId
      timestamp: msg.message.id
    , (result) ->
      resolve result

  mecabTokenize = (unorm_text, robot) -> new Promise (resolve) ->
    data = JSON.stringify {
        "sentence": unorm_text
        "dictionary": 'mecab-ipadic-neologd'
    }
    robot.http(mecabUrl)
      .header("Content-type", "application/json")
      .post(data) (err, res, body) ->
        resolve JSON.parse(body)

  robot.hear /.*?/i, (msg) ->
    if !mecabUrl
      robot.logger.error("You should set HUBOT_SLACK_ULTRASOUL_MECAB_API_URL env variables.")
      return
    unorm_text = unorm.nfkc msg.message.text

    # detect ultrasoul
    mecabTokenize(unorm_text, robot)
    .then (result) ->
      tokens = result.word_list
      targetRegions = [3, 4, 7]
      regions = [0]

      `outer://`
      for token in tokens
        continue if token.pos is '記号'
        for item in ['、', '!', '?']
          if token.surface_form is item
            if regions[regions.length - 1] isnt 0
              regions.push 0
            `continue outer`

        pronunciation = token.pronunciation or token.surface_form
        return unless pronunciation.match /^[ぁ-ゔァ-ヺー…]+$/

        regionLength = pronunciation.replace(/[ぁぃぅぇぉゃゅょァィゥェォャュョ…]/g, '').length

        if ((token.pos) is '助詞' or (token.pos) is '助動詞') or ((token.pos_detail_1) is '接尾' or (token.pos_detail_1) is '非自立')
          regions[regions.length - 1] += regionLength
        else if (regions[regions.length - 1] < targetRegions[regions.length - 1] or regions.length is 3)
          regions[regions.length - 1] += regionLength
        else
          regions.push(regionLength)

      if regions[regions.length - 1] is 0
        regions.pop

      return if regions.length isnt targetRegions.length

      jiamari = checkArrayDifference regions, targetRegions
      jitarazu = checkArrayDifference targetRegions, regions

      return if jitarazu > 0 or jiamari > 1

      addReaction(reaction, msg)
      .then ->
        robot.logger.info "Found ultrasoul! #{msg.message.text}"
        robot.logger.debug "Add recation #{reaction} ts: #{msg.message.id}, channel: #{msg.envelope.room}, text: #{msg.message.text}"

    .catch (error) ->
      robot.logger.error error
