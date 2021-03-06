Site = require "./Site"


class Nhacso extends Site
      constructor: ->
        super "csn"
        @logPath = "./log/CSNLog.txt"
        @log = {}
        @_readLog()

      _getFieldFromTable : (params, callback)->
            _q = "Select #{params.sourceField} from #{params.table}"
            _q += " WHERE #{params.condition} LIMIT #{params.limit}" if params.limit
            @connection.query _q, (err, results)=>
                  callback results
      processSong : (data,options)=>
            song = 
                  id : options.id
                  title : ""
                  artists : null
                  topics : null
                  downloads : 0
                  formats : []
                  href : ""
                  is_lyric : ""
                  date_created : "0001-01-01"
                  # lyric : ""  // it is omitted 
            temp = data.match(/plt-text.+Download: <a href=\"(.+html)\">(.+) - (.+)<\/a><\/div>/)
            if temp
                  song.href = "http://chiasenhac.com/" + temp[1]
                  song.title = @processStringorArray temp[2]
                  song.artists =  @processStringorArray(temp[3]).split(';').map (v)=> @processStringorArray v.trim()
                  temp = temp[0].replace(/\-&gt; Download.+$/,'')
                  temp = temp.split(/\-&gt;/).map (v)-> v.replace(/<\/a>/,'').replace(/^.+>/,'').replace(/\.\.\./,'').trim()
                  _t = []
                  temp.forEach (v,index)->  if index > 0 then v.split(/,/).forEach (v1)-> _t.push v1.trim() else _t.push v
                  _t = _t.map (v)=>  @processStringorArray v.replace(v[0],v[0].toUpperCase())
                  song.topics = _t.filter (element, index, array)-> array.indexOf(element) is index

            downloads = data.match(/<a href=\"http:\/\/download.+\"([0-9]+) downloads/)
            if downloads then song.downloads = parseInt downloads[1],10

            # this part for the diffrent kinds of formats and links
            formats = data.match(/<a href.+Link Download.+/g)
            mobileLink = data.match(/<a href.+Mobile Download.+/g)
            if not formats and mobileLink then  formats = mobileLink
            else if formats and mobileLink then  formats = mobileLink.concat(formats)
            # console.log formats
            if formats
                  formats = formats.map (v)-> 
                          _t = v.match(/<a href=\"(.+)" onmouseover.+Link Download \d: ([a-zA-Z0-9]+) .+>(.+)<\/span> (.+) MB/)
                          if not _t then _t = v.match(/<a href=\"(.+)" onmouseover.+Link Download \d: ([a-zA-Z0-9]+) .+>(Lossless).+> (.+) MB/)
                          if not _t then _t = v.match(/<a href=\"(.+)" onmouseover.+Mobile Download: ([a-zA-Z0-9]+) (.+) (.+) MB/)
                          if not _t then _t = v.match(/<a href=\"(.+)" onmouseover.+Link Download.+: ([a-zA-Z0-9]+) (\d+kbps) (.+) MB/)
                          if not _t then _t = v.match(/<a href=\"(.+)" onmouseover.+Link Download.+([a-zA-Z0-9]+) (.+) (.+) MB/)

                          
                          # console.log v + "-------"
                          if _t
                                _format = 
                                      link : _t[1].replace(/(http.+\/).+(\..+$)/,"$1file-name$2")
                                      type : _t[2].toLowerCase()
                                      file_size : parseFloat(_t[4])*1024|0
                                if song.topics.toString().search('Video Clip') > -1
                                      _format.resolution = _t[3].toLowerCase()
                                else _format.bitrate = _t[3].toLowerCase()
                                return _format
                          else return null
                  # eleminate the null value
                  formats = formats.filter (v)-> if v isnt null then return true else false
                  
                  # replace the link 500kps and lossless with available link,  apply for registered user only
                  # and reduce the link length
                  song.formats = JSON.stringify formats.map (v)-> 
                        if v
                                if v.bitrate is '500kbps'
                                      _temp = "/" + formats[1].bitrate.replace(/kbps/,"") + "/"
                                      v.link = formats[1].link.replace(_temp,'/m4a/').replace(/\.mp3/,'.m4a')
                                if v.bitrate is 'lossless'
                                      _temp = "/" + formats[1].bitrate.replace(/kbps/,"") + "/"
                                      v.link = formats[1].link.replace(_temp,'/flac/').replace(/\.mp3/,'.flac')
                                if v.resolution is "hd 720p"
                                      v.link = formats[1].link.replace(/\/\d{3}\//,'/m4a/').replace(/\.mp3/,'.mp4')
                                if v.resolution is "hd 1080p"
                                      v.link = formats[1].link.replace(/\/\d{3}\//,'/flac/').replace(/\.mp3/,'.mp4')
                        return v

            isLyric = data.match(/(<span class=\"genmed\"><b>.+\s+<span class=\"gen\">).+/)
            if isLyric
                  song.is_lyric = 1
            else song.is_lyric = 0

            dateCreated = data.match(/Upload at (.+)\"/)
            
            if dateCreated 
                  if dateCreated[0].search(/Hôm qua/) > -1 then song.date_created = @formatDate new Date(new Date().getTime()-24*60*60*1000)
                  else if dateCreated[0].search(/Hôm nay/) > -1 then song.date_created = @formatDate(new Date())
                  else song.date_created = dateCreated[1].replace(/(\d+)\/(\d+)\/(\d+) (\d+):(\d+)/,'$3-$2-$1 $4:$5')

            if song.title is "" and song.artists is null and song.formats.length is 0
                  song = null
            
            # console.log song
            @eventEmitter.emit "result-song", song, options
            
            song
      onSongFail : (error, options)=>
            # console.log "Song #{options.id} has an error: #{error}"
            @stats.totalItemCount +=1
            @stats.failedItemCount +=1
            @utils.printRunning @stats
      _getSong : (id)=>
            link = "http://download.chiasenhac.com/download.php?m=#{id}"
            options = 
              id : id
            @getFileByHTTP link, @processSong, @onSongFail, options
      fetchSongs : (range0, range1) =>
            @connect()
            @showStartupMessage "Updating songs to table", @table.Songs
            console.log " |Getting songs from range: #{range0} - #{range1}"
            @stats.currentTable = @table.Songs
            # [range0,range1]=[1030109,1030109]
            @stats.totalItems = range1-range0+1
            @eventEmitter.on "result-song", (song)=>
                    @stats.totalItemCount +=1
                    @stats.passedItemCount +=1
                    # @log.lastSongId = song.songid
                    # @temp.totalFail = 0
                    if song isnt null
                          # console.log song
                          @connection.query @query._insertIntoSongs, song, (err)->
                            if err then console.log "Cannt insert song: #{song.id} into database. ERROR: #{err}"
                    else 
                          @stats.passedItemCount -=1
                          @stats.failedItemCount +=1
                    @utils.printRunning @stats
            
            for id in [range0..range1]
                do (id)=>
                    @_getSong id

      # get song stats : album' name, album link, lyric
      processSongStats : (data, options) =>
            song = options.song
            song.id  = options.id 
            song.authors = null
            song.album_title = ""
            song.album_href = ""
            song.album_coverart = ""
            song.producer = ""
            song.plays = 0
            song.date_released = ""
            song.lyric = ""


            authors = data.match(/>Sáng tác:.+/)?[0]
            if authors
                  song.authors =  authors.split('>;').map (v)=> @processStringorArray v.replace(/<\/a><\/b>.+$/,'').replace(/^.+>/,'').replace(/<\/a.+$|<\/a/,'')

            album = data.match(/>Album:.+/)?[0]
            if album 
                  song.album_title = @processStringorArray album.replace(/<\/a>.+$/,'').replace(/^.+>/,'')
                  song.album_href = album.replace(/^.+<a href=\"/,'').replace(/html.+$/,'html')

            coverart  = data.match(/id=\"fulllyric\".+\s+.+<img src=\"(http.+)\" width/)?[1]
            if coverart then song.album_coverart = coverart

            producer = data.match(/Sản xuất:.+/)?[0]
            if producer then song.producer = @processStringorArray producer.replace(/<\/b>.+$/,'').replace(/^.+<b>/,'').replace(/<a href=.+\">/,'').replace(/<\/a>/,'').trim()

            plays = data.match(/<img.+title=\"([0-9\.]+) listen\"/)?[1]
            if plays then song.plays = parseInt plays.replace(/\./g,''),10

            dateReleased = data.match(/Năm phát hành.+<b>(.+)<\/b>/)
            if dateReleased  then song.date_released = dateReleased[1]
            else if song.producer.search(/\([0-9]{4}\)/) > -1 then song.date_released = song.producer.match(/\(([0-9]{4})\)/)?[1]
            else if song.producer is "" then if song.producer.search(/[0-9]{4}/) > -1 then song.date_released = song.producer.match(/[0-9]{4}/)?[0]

            lyric = data.match(/<p class=\"genmed\"[^]+id=\"morelyric\"/)?[0]
            if lyric then song.lyric = @processStringorArray lyric.replace(/<\/div>[^]+$/,'').replace(/^.+\">/,'')
                                                        .replace(/<span style=\".+com<\/span>/,'')
                                                        .replace(/(on)? ChiaSeNhac.com/g,'').replace(/<\/span>|<\/p>/,'')

            @eventEmitter.emit "result-song-stats", song
            song
      _getSongStat : ->
            params = 
                  sourceField : "id, href"
                  table : @table.Songs
                  limit : 10000
                  condition : " date_released is null ORDER BY id DESC "
            @stats.totalItems = params.limit
            @stats.currentTable = @table.Songs
            @_getFieldFromTable params, (songs)=>
                  # songs = [{id : 2, href : 'http://chiasenhac.com/mp3/vietnam/v-pop/ngay-xua-anh-hoi~minh-tuyet~2.html'}]
                  for song in songs
                        link = song.href
                        options = 
                              id : song.id
                        @getFileByHTTP link, @processSongStats, @onSongFail, options
      fetchSongsStats : ->
            @connect()
            @showStartupMessage "Updating songs stats to table", @table.Songs
            @stats.currentTable = @table.Songs
            @globalCount = 0
            @eventEmitter.on "result-song-stats", (song)=>
                  @stats.totalItemCount +=1
                  @stats.passedItemCount +=1
                  @stats.currentId = song.id
                  if song isnt null
                        _u = " update #{@table.Songs} SET "
                        # _u += " author= #{@connection.escape song.author}, "
                        # _u += " album_title=#{@connection.escape song.album_title}, "
                        # _u += " album_href=#{@connection.escape song.album_href}, "
                        # _u += " album_coverart=#{@connection.escape song.album_coverart}, "
                        # _u += " producer=#{@connection.escape song.producer}, "
                        _u += " plays=#{song.plays}, "
                        # _u += " lyric=#{@connection.escape song.lyric}, "
                        _u += " date_released=#{@connection.escape song.date_released} "
                        _u += " WHERE id=#{song.id} "
                        # console.log _u
                        @connection.query _u,(err)->
                              if err then console.log " Cannot update song #{song.id}. ERROR: #{err}"
                  else 
                        @stats.passedItemCount -=1
                        @stats.failedItemCount +=1
                  @utils.printRunning @stats
                  if @stats.totalItemCount is @stats.totalItems
                        @utils.printFinalResult @stats
                        @globalCount +=1
                        console.log "GOING TO NEXT STEP: #{@globalCount}".inverse.red
                        @resetStats()
                        @_getSongStat()


            @_getSongStat()

      # -------------------------------------------------
      # THIS PART IS FOR UPDATING SONGS
      onUpdateSongStatsFail : (error, options)=>
            # do nothing
      onUpdateSongFail : (error, options)=>
            # console.log "Song #{options.id} has an error: #{error}"
            @stats.totalItemCount +=1
            @stats.failedItemCount +=1
            @temp.totalFail += 1
            @utils.printUpdateRunning song.id, @stats, "Fetching....."
            if @temp.totalFail is @temp.nConsecutiveFailures
                  if @stats.passedItemCount is 0
                        console.log ""
                        console.log "ALL SONGS AND ALBUMS UP-TO-DATE!".red
                  else 
                        @utils.printFinalResult @stats
                        @_writeLog @log
                        @updateAlbums()
            else @_updateSong (options.id+1)
      _updateSong : (id)=>
            link = "http://download.chiasenhac.com/download.php?m=#{id}"
            # console.log link
            options = 
              id : id
            @getFileByHTTP link, @processSong, @onUpdateSongFail, options
      updateSongs : ->
            @connect()
            @showStartupMessage "Updating new songs  to table", @table.Songs
            console.log  " |The program will stop after 100 consecutive failures" , ""
            @stats.currentTable = @table.Songs 
            # condition to halt program
            @temp = 
                  totalFail : 0
                  nConsecutiveFailures : 100
                  reservedLastSongId : @log.lastSongId
            # EVENT TRIGGERED when fetch song is done
            @eventEmitter.on "result-song", (song,options)=>
                  @stats.totalItemCount +=1
                  @stats.passedItemCount +=1
                  
                  if song isnt null
                        @log.lastSongId = song.id
                        @temp.totalFail = 0
                        # console.log song
                        # process.exit 0
                        do (song)=>
                              link = song.href 
                              _options = 
                                    id : song.id
                                    song : song
                              @getFileByHTTP link, @processSongStats, @onUpdateSongStatsFail, _options
                  else 
                        @stats.passedItemCount -=1
                        @stats.failedItemCount +=1
                        @temp.totalFail += 1
                  
                  @utils.printUpdateRunning options.id, @stats, "Fetching....."
                  
                  if @temp.totalFail is @temp.nConsecutiveFailures
                        if @stats.passedItemCount is 0
                              console.log ""
                              console.log "ALL SONGS AND ALBUMS UP-TO-DATE!".red
                        else 
                              @utils.printFinalResult @stats
                              @_writeLog @log
                              @updateAlbums()
                        # console.log "WRITE LOG to DISK"
                  else @_updateSong (options.id+1)

            # EVENT TRIGGERED when fetch song's stats is done
            @eventEmitter.on "result-song-stats", (song)=>

                  # console.log song
                  # process.exit 0
                  if song isnt null
                        @connection.query @query._insertIntoSongs,song, (err)->
                              if err then console.log " Cannot insert song #{song.id}. ERROR: #{err}"
            @_updateSong @log.lastSongId+1

      #NOTICE: CANNT RUN WITHOUT  @temp.reservedLastSongId VARIABLE
      updateAlbums : ->
            @connect()

            # @temp = 
            #     reservedLastSongId : 1122448
            @showStartupMessage "Updating new albums  to table whose new ids > #{@temp.reservedLastSongId}", @table.Albums
            _q = "select max(id) as max from #{@table.Albums}"
            @connection.query _q, (err,result)=>
                  if err then console.log "cannt get max id from table. ERROR: #{err}"
                  else 
                        max = result[0].max
                        _selectQuery = "select title,array_agg_csn_artist_cat(artists) as artists,array_agg_csn_cat(topics) as topics, min(link) as href ,
                              sum(nsongs) as nsongs,max(coverart) as coverart, max(producer) as producer,
                              floor(avg(downloads)) as downloads, floor(avg(plays)) as plays,
                              max(date_released) as date_released , max(date_created) as date_created, array_agg_cat_unique(songids) as songids  
                              from 
                              (
                              select max(album_title) as title,array_agg_csn_artist_cat(artists) as artists,
                              array_agg_csn_cat(topics) as topics , min(album_href) as link, 
                              count(*) as nsongs, album_coverart as coverart, max(producer) as producer, 
                              floor(avg(downloads)) as downloads, floor(avg(plays)) as plays, 
                              max(date_released) as date_released,max(date_created) as date_created, array_agg(id) as songids 
                              from #{@table.Songs} 
                              where id > #{@temp.reservedLastSongId} 
                              and album_title <> '' 
                              and album_href <> '' 
                              group by album_coverart 
                              ) as anbinh
                              group by title".replace(/\s{4}/g,' ').replace(/\s{4}/g,' ').replace(/\s{4}/g,' ')
                        # console.log _selectQuery
                        @connection.query _selectQuery, (err1,albums)=>
                              if err1 then console.log "Cannt query new albums from available songs. ERROR:#{err1}"
                              else
                                    console.log "The total new albums: #{albums.length}" 
                                    for album in albums
                                          album.nsongs = parseInt(album.nsongs,10)
                                          album.downloads = parseInt(album.downloads,10)
                                          album.plays = parseInt(album.plays,10)
                                          album.date_created = @formatDate album.date_created
                                          # console.log album
                                          # process.exit 0
                                          @connection.query @query._insertIntoAlbums,album, (err)->
                                                if err then console.log " Cannot insert album #{album.id}. ERROR: #{err}"
                                    if albums.length > 0 then  console.log "UPDATING ALBUMS DONE!".green
                                    else console.log "ALL ALBUMS UP-TO-DATE!".red



      # THIS PART RUN ONCE ONLY. IT IS SUPPOSED TO FETCH VIDEO FROM CHIASENHAC WHOSE IDS ARE LESS THAN 10^5
      updateVideoLessthan10exp5 : ->
            @connect()
            @showStartupMessage "Updating new hrefs  to table", @table.Songs
            @stats.currentTable = @table.Songs 
            @eventEmitter.on "result-song", (song,options)=>
                  @stats.totalItemCount +=1
                  @stats.passedItemCount +=1
                  
                  if song isnt null
                        # console.log song
                        _u = "UPDATE #{table.Songs} set formats = #{@connection.escape song.formats} where id=#{song.id}"
                        # console.log _u 
                        @connection.query _u, (err)->
                             if err then console.log "CANNTO INSER SSONGS #{song.id}------#{err}"
                  else 
                        @stats.passedItemCount -=1
                        @stats.failedItemCount +=1
                        @temp.totalFail += 1
                  
                  @utils.printRunning @stats
                  
                  if @stats.totalItems is @stats.totalItemCount
                      @utils.printFinalResult @stats
            _select = "select id from #{table.Songs} where id < 100000 and topic like '[\"Video Clip%' "
            @connection.query _select, (err, results)=>
                  if err then console.log "EROROORORORO"
                  else 
                        @stats.totalItems = results.length
                        console.log "total item #{@stats.totalItems}"
                        for song in results
                              @_getSong song.id

      showStats : ->
        @_printTableStats @table


module.exports = Nhacso





