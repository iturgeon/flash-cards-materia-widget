# Create an angular module to import the animation module and house our controller
Flashcards = angular.module 'FlashcardsCreator', ['ngAnimate', 'ngSanitize']

Flashcards.directive 'ngEnter', ->
	return (scope, element, attrs) ->
		element.bind "keydown keypress", (event) ->
			if event.which == 13
				scope.$apply -> scope.$eval(attrs.ngEnter)
				event.preventDefault()

Flashcards.directive 'focusMeWatch', ['$timeout', '$parse', ($timeout, $parse) ->
	link: (scope, element, attrs) ->
		model = $parse(attrs.focusMe)
		scope.$watch model, (value) ->
			if value
				$timeout -> element[0].focus()
			value
]

Flashcards.directive 'focusMe', ['$timeout', ($timeout) ->
	scope:
		condition: "=focusMe"
	link: (scope, element, attrs) ->
		if scope.condition
			$timeout -> element[0].focus()
]
# Directive that handles all media imports & removals
Flashcards.directive 'importAsset', ['$http', '$timeout', ($http, $timeout) ->
	template: '<div id="{{myId}}"></div><button class="del-asset" aria-label="Remove media" ng-hide="!cardFace.asset" ng-click="deleteAsset()"><span class="icon-close"></span><span class="descript del">remove media</span></button><button aria-label="Add media." ng-hide="cardFace.asset" ng-click="addAsset()" ng-attr-tabindex="{{startingTabIndex + 1 + (face == "front" ? 0 : 2)}}"><span class="icon-image"></span><span class="descript add">add media</span></button>'
	scope:
		cardFace: '='
		mediaImport: '='
		requestMediaImport: '='
		asset: '='

	link: (scope, element, attrs) ->
		scope.myId = Math.floor(Math.random() * 100000) + '-import-asset'

		insertAsset = (assetType, url) ->
			# Variable used by importAsset directive
			el = angular.element(document.getElementById(scope.myId))

			asset = switch assetType.toLowerCase()
				when 'link', 'youtube', 'vimeo'
					'<iframe width="49%" height="140" src="' + url + '" frameborder="0" allowfullscreen sandbox="allow-scripts allow-same-origin allow-forms" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture"></iframe>'
				when 'mp4'
					'<video width="280" height="140" controls>
						<source src="' + url + '" type="video/mp4">
					</video>'
				when 'mp3', 'wav'
					'<audio controls src="' + url + '"></audio>'
				when 'jpg', 'jpeg', 'png', 'gif'
					'<img src="' + url + '">'
				else null

			if asset?
				el.empty()
				el.append(asset)

		scope.deleteAsset = ->
			scope.cardFace.asset = ''
			el = angular.element(document.getElementById(scope.myId))
			el.empty()
			null

		scope.addAsset = ->
			# forces all previous watches to stop and resets the asset value
			scope.mediaImport.assetUrl = null
			# stopWatching = scope.$watch 'mediaImport.assetUrl', insertAsset
			scope.requestMediaImport(scope.cardFace, insertAsset)

		# populates cards with assets during Edit Widget
		if scope.asset.id?.length > 0
			$timeout -> insertAsset(scope.asset.type, scope.asset.url)
		# Fallback for older QSets (asset is a string providing the ID, not an object)
		else if scope.asset.length > 0
			$timeout -> insertAsset('png', Materia.CreatorCore.getMediaUrl(scope.asset))
]

# Set the controller for the scope of the document body.
Flashcards.controller 'FlashcardsCreatorCtrl', ['$scope', '$sanitize', ($scope, $sanitize) ->
	SCROLL_DURATION_MS = 500
	WHEEL_DELTA_THRESHOLD = 5
	mediaImportWatcher = null

	# keep track of any characters that play havoc with $sanitize here to pre-sanitize them
	PRESANITIZE_CHARACTERS =
		'>': '&gt;',
		'<': '&lt;'

	$scope.FACE_BACK = 0
	$scope.FACE_FRONT = 1
	$scope.MAX_CARDS = 300
	$scope.ACTION_CREATE_NEW_CARD = 'create'
	$scope.ACTION_IMPORT = 'import'
	$scope.title = "My Flash Cards widget"
	$scope.cards = []
	$scope.introCompleted = false

	scrollDownIntervalId = null
	scrollDownTimeoutId = null

	$scope.faceWaitingForMedia = null
	$scope.mediaImport =
		mediaId: null
		assetType: null
		assetUrl: null

	$scope.acceptedMediaTypes = ['image', 'audio', 'video']

	decodeHtmlEntity = (str) ->
		# replace html entities with their non-entity characters
		str = str.replace /\&#(\d+);/g, (match, char) ->
			a = String.fromCharCode char
			return a
		# replace any specific characters we might have pre-sanitized before saving
		for k, v of PRESANITIZE_CHARACTERS
			str = str.replace new RegExp(v, 'g'), k
		return str

	importCards = (items) ->
		$scope.lastAction = $scope.ACTION_IMPORT

		for item in items
			$scope.addCard item

		$scope.$apply()

	# View actions
	$scope.setTitle = ->
		$scope.title = $scope.introTitle or $scope.title
		$scope.introCompleted = true
		$scope.hideCover()

	$scope.hideCover = ->
		$scope.showTitleDialog = $scope.showIntroDialog = $scope.showSizeWarningDialog = false

	$scope.initNewWidget = (widget, baseUrl) ->
		$scope.$apply ->
			$scope.showIntroDialog = true

	$scope.initExistingWidget = (title, widget, qset, version, baseUrl) ->
		$scope.title = decodeHtmlEntity title
		importCards qset.items[0].items

	$scope.onSaveClicked = (mode = 'save') ->

		# Decide if it is ok to save
		if $scope.title is ''
			Materia.CreatorCore.cancelSave 'Please enter a title.'
			return false

		for card, i in $scope.cards
			if card.front.text.length > 50 and card.front.asset
				Materia.CreatorCore.cancelSave 'Please reduce the text of the front of card #'+(i+1)+' to fit the card.'
				return false
			if card.back.text.length > 50 and card.back.asset
				Materia.CreatorCore.cancelSave 'Please reduce the text of the back of card #'+(i+1)+' to fit the card.'
				return false

		Materia.CreatorCore.save $scope.title, buildQsetFromCards($scope.cards)

	$scope.onSaveComplete = -> true

	$scope.onQuestionImportComplete = importCards.bind(@)

	$scope.createNewCard = ->
		if $scope.cards.length < $scope.MAX_CARDS
			$scope.lastAction = $scope.ACTION_CREATE_NEW_CARD;
			$scope.addCard()
			scrollToBottom()
		else
			$scope.showSizeWarningDialog = true;

	$scope.requestMediaImport = (cardFace, callback) ->
		# Save the card/face that requested the image
		$scope.faceWaitingForMedia = cardFace
		mediaImportWatcher() if mediaImportWatcher?
		mediaImportWatcher = $scope.$watch 'mediaImport.assetUrl', (newValue, oldValue) ->

			return if newValue == oldValue # do nothing
			callback($scope.mediaImport.assetType, $scope.mediaImport.assetUrl)

		Materia.CreatorCore.showMediaImporter($scope.acceptedMediaTypes)

	$scope.onMediaImportComplete = (media) ->
		if ! media?[0]?.id?
			$scope.faceWaitingForMedia = null
			return

		m = media[0]

		$scope.faceWaitingForMedia.asset =
			id: m.id
			type: m.type
			url: (if m.remote_url? then m.remote_url else $scope.getMediaUrl(m.id))


		# Variables used by importAsset directive
		$scope.mediaImport.mediaId = m.id
		$scope.mediaImport.assetType = m.type
		$scope.mediaImport.assetUrl = $scope.faceWaitingForMedia.asset.url

		$scope.$apply()

	$scope.getMediaUrl = (asset) ->
		if not asset or asset is '-1' then return ''
		Materia.CreatorCore.getMediaUrl(asset)

	$scope.addCard = (item) ->
		$scope.cards.push
			id: item?.id || ''
			front:
				text: decodeHtmlEntity item?.questions?[0]?.text?.replace(/\&\#10\;/g, '\n') || ''
				id: item?.questions?[0]?.id || ''
				asset: item?.assets?[0] || ''
			back:
				text: decodeHtmlEntity item?.answers?[0]?.text?.replace(/\&\#10\;/g, '\n') || ''
				id: item?.answers?[0]?.id || ''
				asset: item?.assets?[1] || ''

	$scope.removeCard = (index) ->
		$scope.cards.splice index, 1

	buildQsetFromCards = (cards) ->
		items = []

		for card in cards
			items.push getQsetItemFromCard(card)

		options: {}
		assets: []
		rand: false
		name: ''
		items: [{items:items}]

	getQsetItemFromCard = (card) ->
		sanitizedQuestion = $sanitize preSanitize(card.front.text)
		sanitizedAnswer   = $sanitize preSanitize(card.back.text)

		materiaType: 'question'
		type: 'QA'
		id: card.id
		questions: [{id:card.front.id, text:sanitizedQuestion}]
		answers: [{id:card.back.id, text:sanitizedAnswer, value:'100'}]
		assets: [card.front.asset, card.back.asset]

	# replace a specified list of characters with their safe equivalents
	preSanitize = (text) ->
		for k, v of PRESANITIZE_CHARACTERS
			text = text.replace new RegExp(k, 'g'), v
		return text

	scrollToBottom = ->
		clearInterval scrollDownTimeoutId
		if scrollDownIntervalId is null
			scrollDownIntervalId = setInterval ->
				window.scrollTo 0, document.body.scrollHeight
			, 10
		scrollDownTimeoutId = setTimeout clearScroll, SCROLL_DURATION_MS

	clearScroll = ->
		clearInterval scrollDownIntervalId
		scrollDownIntervalId = null

	window.addEventListener 'mousewheel', clearScroll.bind(@)

	Materia.CreatorCore.start $scope
]
