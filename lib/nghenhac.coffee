http = require 'http'
xml2js = require 'xml2js'
Module = require './module'
Utils = require './utils'
colors = require 'colors'
fs = require 'fs'

events = require('events')
Encoder = require('node-html-encoder').Encoder
encoder = new Encoder('entity');

NN_CONFIG = 
	table : 
		Songs : "NNSongs"
		Albums : "NNAlbums"
		Songs_Albums : "NNSongs_Albums"
	logPath : "./log/NNLog.txt"

class Nghenhac extends Module
	constructor : (@mysqlConfig, @config = NN_CONFIG) ->
		@table = @config.table
		@query = 
			_insertIntoNNSongs : "INSERT INTO " + @table.Songs + " SET ?"
			_insertIntoNNAlbums : "INSERT INTO " + @table.Albums + " SET ?"
			_insertIntoNNSongs_Albums : "INSERT INTO " + @table.Songs_Albums + " SET ?"
		@utils = new Utils()
		@parser = new xml2js.Parser();
		@eventEmitter = new events.EventEmitter()
		super @mysqlConfig
		
		@logPath = @config.logPath
		@log = {}
		@_readLog()	
	getFileByHTTP : (link, onSucess, onFail, options) ->
		http.get link, (res) =>
				res.setEncoding 'utf8'
				data = ''
				# onSucess res.headers.location
				if res.statusCode isnt 302
					res.on 'data', (chunk) =>
						data += chunk;
					res.on 'end', () =>
						
						onSucess data, options
				else onFail("The link is temporary moved",options)
			.on 'error', (e) =>
				onFail  "Cannot get file from server. ERROR: " + e.message, options

	processSong : (data,options)=>
		song =
			id : options.id
			encoded_id : ""
			name : ""
			artist_id : 0
			artist : ""
			author : ""
			albumid : 0
			topic : ""
			plays : 0
			lyric : ""
			link : ""

		a = ["Nhac-tre","Nhac-hai-ngoai","Nhac-Viet-Nam","Nhac-trinh","Nhac-tien-chien","Nhac-dan-toc","Nhac-do","Nhac-Cach-mang","Nhac-Tru-tinh","Nhac-Vang","Nhac-thieu-nhi","Nhac-que-huong","Tat-ca","Nhac-Au-My","Nhac-phim","Viet-Nam","Han-Quoc","Trung-Quoc","Quoc-te","Quang-cao","Nhac-khong-loi","Hoa-tau","Giao-huong","Rap-Viet","Rock-Viet","Nhac-Han","Nhac-Hoa","Nhac-Nhat","Flash-music","Nhac-Phap","TeenPops","RB","RocknRoll","NewAge"]
		b = ["Nhạc Trẻ","Nhạc Hải Ngoại","Nhạc Việt Nam","Nhạc Trịnh","Nhạc Tiền Chiến","Nhạc Dân Tộc","Nhạc Đỏ","Nhạc Cách Mạng","Nhạc Trữ Tình","Nhạc Vàng","Nhạc Thiếu Nhi","Nhạc Quê Hương","Tất cả","Nhạc Âu Mỹ","Nhạc Phim","Việt Nam","Hàn Quốc","Trung Quốc","Quốc Tế","Quảng Cáo","Nhạc Không Lời","Hòa Tấu","Giao Hưởng","Rap Việt","Rock Việt","Nhạc Hàn","Nhạc Hoa","Nhạc Nhật","Flash music","Nhạc Pháp","Teen Pop","R&B","Rock & Roll","New Age"]

		encoded_id = data.match(/ashx\?p=[a-zA-Z0-9]+/)?[0]
		if encoded_id isnt undefined
			song.encoded_id = encoded_id.replace(/ashx\?p=/g,'')

		name = data.match(/Ca\skhúc:.+/g)?[0]
		if name isnt undefined
			song.name = encoder.htmlDecode name.replace(/<\/span>.+$/g,'').replace(/^.+>/g,'')

		artist = data.match(/Trình\sbày:.+/g)?[0]
		if artist isnt undefined
			artist_id = artist.match(/Song\/\d+/g,'')?[0].match(/\d.+/g)?[0]
			if artist_id isnt undefined
				song.artist_id = artist_id
			artist = artist.replace(/<\/a>.+$/g,'').replace(/^.+>/g,'')
			if artist isnt "Chưa xác định"
				song.artist = encoder.htmlDecode artist

		author = data.match(/Tác\sgiả:.+/g)?[0]
		if author isnt undefined
			author = author.replace(/<\/a>.+$/g,'').replace(/^.+>/g,'')
			if author isnt "Chưa xác định"
				song.author = encoder.htmlDecode author

		albumid = data.match(/Album:.+/g)?[0]
		if albumid isnt undefined
			albumid =  albumid.match(/\/Album\/.+\/\d+/g)?[0]?.match(/\d+/)?[0]
			if albumid isnt undefined
				song.albumid = albumid

		topic = data.match(/href.+Index\.html.+»\sXem\stất\scả/)?[0]
		if topic isnt undefined
			topic = topic.replace(/href=\"\//g,'').replace(/\/Index.+$/g,'').split(/\//)
			song.topic = JSON.stringify topic.map (v)->
				if a.indexOf(v) > -1
					b[a.indexOf(v)]
				else v


		plays = data.match(/Bầu\schọn:.+/)?[0]
		if plays isnt undefined
			points = plays.match(/\d+\sđiểm/)?[0]
			times = plays.match(/\d\slần/)?[0]
			song.plays =  parseInt(points,10) + parseInt(times,10)

		lyric = data.match(/id=\"lyric\".+/g,'')?[0]
		if lyric isnt undefined
			song.lyric = encoder.htmlDecode lyric.replace(/<\/div>$/g,'').replace(/^.+\">/g,'')

		link = data.match(/mp3:\s\'http:\/\/.+/g,'')?[0]
		if link isnt undefined
			song.link = link.replace(/^.+http/g,'http').replace("'","")

		@eventEmitter.emit 'result', song
		song
	_fetchSong : (id)->
		options = 
			id : id
		link = "http://nghenhac.info/joke/#{id}/joke.html"
		onFail = (err)=>
			@stats.totalItemCount += 1
			@stats.failedItemCount +=1
			@utils.printRunning @stats
			if @stats.totalItems is @stats.totalItemCount
				@utils.printFinalResult @stats
			# console.log err
		@getFileByHTTP link, @processSong, onFail, options
	fetchSongs : (range0 = 0, range1 = 0) =>
		@connect()
		console.log " |"+"Fetching songid: #{range0}..#{range1} to table: #{@table.Songs}".magenta
		@stats.totalItems = (range1 - range0 + 1)
		[@stats.range0, @stats.range1] = [range0, range1]
		@stats.currentTable = @table.Songs
		@eventEmitter.on 'result', (song)=>
			@stats.totalItemCount += 1
			@stats.passedItemCount +=1
			@stats.currentId = song.id
			@utils.printRunning @stats
			if @stats.totalItems is @stats.totalItemCount
				@utils.printFinalResult @stats
			
			@connection.query @query._insertIntoNNSongs, song, (err)->
				if err then console.log "Cannt insert song: #{song.id} into table. ERROR : #{err}"
		@_fetchSong id for id in [range0..range1]
		
	processAlbum : (data,options)=>
		album = 
			id : options.id
			encoded_id : ""
			name : ""
			artist : ""
			topic : ""
			nsongs : 0
			plays : 0
			thumbnail : ""
			songs : []

		a = ["Nhac-tre","Nhac-hai-ngoai","Nhac-Viet-Nam","Nhac-trinh","Nhac-tien-chien","Nhac-dan-toc","Nhac-do","Nhac-Cach-mang","Nhac-Tru-tinh","Nhac-Vang","Nhac-thieu-nhi","Nhac-que-huong","Tat-ca","Nhac-Au-My","Nhac-phim","Viet-Nam","Han-Quoc","Trung-Quoc","Quoc-te","Quang-cao","Nhac-khong-loi","Hoa-tau","Giao-huong","Rap-Viet","Rock-Viet","Nhac-Han","Nhac-Hoa","Nhac-Nhat","Flash-music","Nhac-Phap","TeenPops","RB","RocknRoll","NewAge"]
		b = ["Nhạc Trẻ","Nhạc Hải Ngoại","Nhạc Việt Nam","Nhạc Trịnh","Nhạc Tiền Chiến","Nhạc Dân Tộc","Nhạc Đỏ","Nhạc Cách Mạng","Nhạc Trữ Tình","Nhạc Vàng","Nhạc Thiếu Nhi","Nhạc Quê Hương","Tất cả","Nhạc Âu Mỹ","Nhạc Phim","Việt Nam","Hàn Quốc","Trung Quốc","Quốc Tế","Quảng Cáo","Nhạc Không Lời","Hòa Tấu","Giao Hưởng","Rap Việt","Rock Việt","Nhạc Hàn","Nhạc Hoa","Nhạc Nhật","Flash music","Nhạc Pháp","Teen Pop","R&B","Rock & Roll","New Age"]


		encoded_id = data.match(/PlayAlbumJson\.ashx\?p\=[0-9a-zA-Z]+/g)?[0]
		if encoded_id isnt undefined
			album.encoded_id = encoded_id.replace(/PlayAlbumJson\.ashx\?p\=/g,'')

		name =  data.match(/\<span\>Nghe\sAlbum.+\<\/span\>/g)?[0]
		if name isnt undefined
			album.name = name.replace(/\<span\>Nghe\sAlbum\s:/g,'').replace(/\<\/span\>/g,'').trim()

		artist = data.match(/Trình\sbày:.+/g)?[0]
		if artist isnt undefined
			album.artist = artist.replace(/<a\/>.+$/g,'').replace(/^.+>/g,'')

		topic = data.match(/href.+Index\.html.+a_Genreviewall/)?[0]
		if topic isnt undefined
			topic = topic.replace(/href=\"\//g,'').replace(/\/Album\/1\/Index.+$/g,'').split(/\//)
			album.topic = JSON.stringify topic.map (v)->
				if a.indexOf(v) > -1
					b[a.indexOf(v)]
				else v

		songs = data.match(/<a\sclass=\"link-black\"\stitle=\"Nghe.+/g)
		if songs isnt null
			album.nsongs = songs.length
			album.songs = songs.map (v)-> 
				t = v.match(/\/\d+\//g)?[0]
				if t isnt undefined
					t.replace(/\//g,'')
				else 
					0

		if data.match(/Chưa\sbầu\schọn\slần\snào/g) is null
			plays = data.match(/Bầu\schọn\:.+/g)?[0]
			if plays isnt undefined
				album.plays = plays.replace(/\<.+\>/g,'').replace(/Bầu\schọn\:\s\(/g,'')
						.replace(/\slần\)/g,'')
						.replace(/\sđiểm/g,'').trim()
						.split(',').reduce((x,y)-> parseInt(x,10)+parseInt(y,10))

		thumbnail = data.match(/AlbumImage.+/g)?[0]
		if thumbnail isnt undefined
			album.thumbnail = thumbnail.replace(/\"\s\/><\/div>/g,'').replace(/^.+\"/g,'')

		@eventEmitter.emit 'result-album', album
		album
	_fetchAlbum : (id) ->
		options = 
			id : id
		link = "http://nghenhac.info/Album/joke-link/#{id}/.html"
		onFail = (err)=>
			@stats.totalItemCount += 1
			@stats.failedItemCount +=1
			@utils.printRunning @stats
			if @stats.totalItems is @stats.totalItemCount
				@utils.printFinalResult @stats
			# console.log err
		@getFileByHTTP link, @processAlbum, onFail, options
	fetchAlbums : (range0 = 0, range1 = 0) =>
		@connect()
		console.log " |"+"Fetching albumid: #{range0}..#{range1} to table: #{@table.Albums}".magenta
		@stats.totalItems = (range1 - range0 + 1)
		[@stats.range0, @stats.range1] = [range0, range1]
		@stats.currentTable = @table.Albums
		@eventEmitter.on 'result', (album)=>
			# console.log album
			@stats.totalItemCount += 1
			@stats.passedItemCount +=1
			@stats.currentId = album.id
			@utils.printRunning @stats
			if @stats.totalItems is @stats.totalItemCount
				@utils.printFinalResult @stats
			
			songs = album.songs
			delete album.songs
			@connection.query @query._insertIntoNNAlbums, album, (err)=>
				if err then console.log "Cannt insert album: #{album.id} into table. ERROR : #{err}"
				else 
					for sid in songs
						do (sid)=>
							@connection.query @query._insertIntoNNSongs_Albums, {aid : album.id, sid : sid}, (err1)->
								if err1 then console.log "cannt insert song: #{sid} - album: #{album.id} into table. ERROR: #{err1}"

		@_fetchAlbum id for id in [range0..range1]
		null

	_updateAlbum : (id)->
		options = 
			id : id
		link = "http://nghenhac.info/Album/joke-link/#{id}/.html"
		onFail = (err, options)=>
			@stats.totalItemCount +=1
			@stats.failedItemCount +=1
			@temp.totalFail +=1

			@utils.printUpdateRunning options.id, @stats, "Fetching..."
			if @temp.totalFail < 100
				@_updateAlbum options.id+1
			else 
				if @stats.passedItemCount is 0
					console.log ""
					console.log "Album up-to-date"
				else 
					@utils.printFinalResult @stats
					@_writeLog @log

		@getFileByHTTP link, @processAlbum, onFail, options
	updateAlbums : ->
		@connect()
		@_readLog()
		@temp = 
			totalFail : 0
		@stats.currentTable = @table.Albums
		console.log " |"+"Updating Albums to table: #{@table.Albums}".magenta

		@eventEmitter.on 'result-album', (album)=>
			@stats.totalItemCount +=1
			@stats.passedItemCount +=1
			@log.lastAlbumId = album.id
			@temp.totalFail = 0
			@utils.printUpdateRunning album.id, @stats, "Fetching..."
			# console.log album
			songs = album.songs
			delete album.songs
			@connection.query @query._insertIntoNNAlbums, album, (err)=>
				if err then console.log "Cannot insert album: #{album.id} into table. ERROR : #{err}"
				else 
					for sid in songs
						do (sid)=>
							@connection.query @query._insertIntoNNSongs_Albums, {aid : album.id, sid : sid}, (err1)->
								if err1 then console.log "Cannot insert song: #{sid} - album: #{album.id} into table. ERROR: #{err1}"
			@_updateAlbum(album.id+1) 
		@_updateAlbum(@log.lastAlbumId+1)

	_updateSong : (id)->
		options = 
			id : id
		link = "http://nghenhac.info/joke/#{id}/joke.html"
		onFail = (err, options)=>
			@stats.totalItemCount +=1
			@stats.failedItemCount +=1
			@temp.totalFail +=1

			@utils.printUpdateRunning options.id, @stats, "Fetching..."
			if @temp.totalFail < 100
				@_updateSong options.id+1
			else 
				if @stats.passedItemCount is 0
					console.log ""
					console.log "Song up-to-date"
				else 
					@utils.printFinalResult @stats
					@_writeLog @log

				# running updating album complete
				@resetStats()
				@updateAlbums()

		@getFileByHTTP link, @processSong, onFail, options
	update : ->
		@connect()
		@_readLog()
		@temp = 
			totalFail : 0
		@stats.currentTable = @table.Songs
		console.log " |"+"Updating Songs to table: #{@table.Songs}".magenta

		@eventEmitter.on 'result', (song)=>
			@stats.totalItemCount +=1
			@stats.passedItemCount +=1
			@log.lastSongId = song.id
			@temp.totalFail = 0
			@utils.printUpdateRunning song.id, @stats, "Fetching..."
			@connection.query @query._insertIntoNNSongs, song, (err)->
				if err then console.log "Cannt insert song: #{song.id} into table. ERROR : #{err}"
			@_updateSong(song.id+1) 
		@_updateSong(@log.lastSongId+1)


	showStats : ->
		@_printTableStats NN_CONFIG.table


module.exports = Nghenhac
