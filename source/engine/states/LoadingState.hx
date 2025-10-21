package states;

#if (target.threaded)
import sys.thread.Thread;
import sys.thread.Mutex;
#end
import lime.utils.Assets;
import openfl.display.BitmapData;
import openfl.utils.AssetType;
import openfl.utils.Assets as OpenFlAssets;
import flixel.addons.transition.FlxTransitionableState;
import flixel.graphics.FlxGraphic;
import flixel.FlxState;
import backend.Song;
import backend.StageData;
import objects.Character;

class LoadingState extends MusicBeatState
{
	public static var loaded:Int = 0;
	public static var loadMax:Int = 0;

	static var requestedBitmaps:Map<String, BitmapData> = [];
	#if (target.threaded)
	static var mutex:Mutex = new Mutex();
	#end

	function new(target:FlxState, stopMusic:Bool)
	{
		this.target = target;
		this.stopMusic = stopMusic;
		startThreads();

		super();
	}

	inline static public function loadAndSwitchState(target:FlxState, stopMusic = false, intrusive:Bool = true)
		MusicBeatState.switchState(getNextState(target, stopMusic, intrusive));

	var target:FlxState = null;
	var stopMusic:Bool = false;
	var dontUpdate:Bool = false;

	var bar:FlxSprite;
	var barWidth:Int = 0;
	var intendedPercent:Float = 0;
	var curPercent:Float = 0;
	var canChangeState:Bool = true;

	var loadingText:FlxText;

	var timePassed:Float;
	var shakeFl:Float;
	var shakeMult:Float = 0;

	var isSpinning:Bool = false;
	var pressedTimes:Int = 0;

	override function create()
	{
		if (checkLoaded())
		{
			dontUpdate = true;
			super.create();
			onLoad();
			return;
		}

		add(new FlxSprite(0, 0).makeGraphic(FlxG.width, FlxG.height, 0xffcaff4d));

		var bg = new FlxSprite(0, 0, Paths.image('funkay'));
		bg.setGraphicSize(0, FlxG.height);
		bg.updateHitbox();
		bg.screenCenter();
		add(bg);

		var bottomBG = new FlxSprite(0, FlxG.height - 26).makeGraphic(FlxG.width, 26, 0xFF000000);
		bottomBG.alpha = 0.6;
		add(bottomBG);

		loadingText = new FlxText(520, 600, 400, 'Now Loading...', 32);
		loadingText.setFormat(Paths.font("Comfortaa-Bold.ttf"), 32, FlxColor.WHITE, LEFT, OUTLINE_FAST, FlxColor.BLACK);
		loadingText.borderSize = 2;
		add(loadingText);

		var bgBar:FlxSprite = new FlxSprite(0, 660).makeGraphic(1, 1, FlxColor.BLACK);
		bgBar.scale.set(FlxG.width - 300, 25);
		bgBar.updateHitbox();
		bgBar.screenCenter(X);
		add(bgBar);

		bar = new FlxSprite(bgBar.x + 5, bgBar.y + 5).makeGraphic(1, 1, FlxColor.WHITE);
		bar.scale.set(0, 15);
		bar.updateHitbox();
		add(bar);
		barWidth = Std.int(bgBar.width - 10);

		persistentUpdate = true;
		super.create();
	}

	var transitioning:Bool = false;

	override function update(elapsed:Float)
	{
		super.update(elapsed);
		if (dontUpdate)
			return;

		if (!transitioning)
		{
			if (canChangeState && !finishedLoading && checkLoaded())
			{
				transitioning = true;
				onLoad();
				return;
			}
			intendedPercent = loaded / loadMax;
		}

		if (curPercent != intendedPercent)
		{
			if (Math.abs(curPercent - intendedPercent) < 0.001)
				curPercent = intendedPercent;
			else
				curPercent = FlxMath.lerp(intendedPercent, curPercent, Math.exp(-elapsed * 15));

			bar.scale.x = barWidth * curPercent;
			bar.updateHitbox();
		}

		timePassed += elapsed;
		shakeFl += elapsed * 3000;
		var txt:String = 'Now Loading.';
		switch (Math.floor(timePassed % 1 * 3))
		{
			case 1:
				txt += '.';
			case 2:
				txt += '..';
		}
		loadingText.text = txt;
	}

	var finishedLoading:Bool = false;

	function onLoad()
	{
		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();

		imagesToPrepare = [];
		soundsToPrepare = [];
		musicToPrepare = [];
		songsToPrepare = [];

		FlxG.camera.visible = false;
		// FlxTransitionableState.skipNextTransIn = true;
		MusicBeatState.switchState(target);
		transitioning = true;
		finishedLoading = true;
	}

	static function checkLoaded():Bool
	{
		for (key => bitmap in requestedBitmaps)
		{
			if (bitmap != null && Paths.cacheBitmap(key, bitmap) != null)
				trace('finished preloading image $key');
			else
				trace('failed to cache image $key');
		}
		requestedBitmaps.clear();
		return (loaded == loadMax);
	}

	static function getNextState(target:FlxState, stopMusic = false, intrusive:Bool = true):FlxState
	{
		var directory:String = 'shared';
		var weekDir:String = StageData.forceNextDirectory;
		StageData.forceNextDirectory = null;

		if (weekDir != null && weekDir.length > 0 && weekDir != '')
			directory = weekDir;

		Paths.setCurrentLevel(directory);
		trace('Setting asset folder to ' + directory);

		var doPrecache:Bool = false;
		if (ClientPrefs.data.loadingScreen)
		{
			clearInvalids();
			if (intrusive)
			{
				if (imagesToPrepare.length > 0 || soundsToPrepare.length > 0 || musicToPrepare.length > 0 || songsToPrepare.length > 0)
					return new LoadingState(target, stopMusic);
			}
			else
				doPrecache = true;
		}

		if (stopMusic && FlxG.sound.music != null)
			FlxG.sound.music.stop();

		if (doPrecache)
		{
			startThreads();
			while (true)
			{
				if (checkLoaded())
				{
					imagesToPrepare = [];
					soundsToPrepare = [];
					musicToPrepare = [];
					songsToPrepare = [];
					break;
				}
				else
					#if sys Sys.sleep(0.01); #else haxe.Timer.delay(() -> {}, 10); #end
			}
		}
		return target;
	}

	static var imagesToPrepare:Array<String> = [];
	static var soundsToPrepare:Array<String> = [];
	static var musicToPrepare:Array<String> = [];
	static var songsToPrepare:Array<String> = [];

	public static function prepare(images:Array<String> = null, sounds:Array<String> = null, music:Array<String> = null)
	{
		if (images != null)
			imagesToPrepare = imagesToPrepare.concat(images);
		if (sounds != null)
			soundsToPrepare = soundsToPrepare.concat(sounds);
		if (music != null)
			musicToPrepare = musicToPrepare.concat(music);
	}

	static var dontPreloadDefaultVoices:Bool = false;

	public static function prepareToSong()
	{
		if (!ClientPrefs.data.loadingScreen)
			return;

		var song:SwagSong = PlayState.SONG;
		var folder:String = Paths.formatToSongPath(song.song);
		try
		{
			var path:String = Paths.json('$folder/preload');
			var json:Dynamic = null;

			#if MODS_ALLOWED
			var moddyFile:String = Paths.modsJson('$folder/preload');
			if (FileSystem.exists(moddyFile))
				json = haxe.Json.parse(File.getContent(moddyFile));
			else
				json = haxe.Json.parse(File.getContent(path));
			#else
			json = haxe.Json.parse(Assets.getText(path));
			#end

			if (json != null)
				prepare((!ClientPrefs.data.lowQuality || json.images_low) ? json.images : json.images_low, json.sounds, json.music);
		}
		catch (e:Dynamic)
		{
		}

		if (song.stage == null || song.stage.length < 1)
			song.stage = StageData.vanillaSongStage(folder);

		var stageData:StageFile = StageData.getStageFile(song.stage);
		if (stageData != null && stageData.preload != null)
			prepare((!ClientPrefs.data.lowQuality || stageData.preload.images_low) ? stageData.preload.images : stageData.preload.images_low,
				stageData.preload.sounds, stageData.preload.music);

		songsToPrepare.push('$folder/Inst');

		var player1:String = song.player1;
		var player2:String = song.player2;
		var gfVersion:String = song.gfVersion;
		var needsVoices:Bool = song.needsVoices;
		var prefixVocals:String = needsVoices ? '$folder/Voices' : null;
		if (gfVersion == null)
			gfVersion = 'gf';

		dontPreloadDefaultVoices = false;
		preloadCharacter(player1, prefixVocals);
		if (player2 != player1)
			preloadCharacter(player2, prefixVocals);
		if (!stageData?.hide_girlfriend && gfVersion != player2 && gfVersion != player1)
			preloadCharacter(gfVersion);

		if (!dontPreloadDefaultVoices && needsVoices)
			songsToPrepare.push(prefixVocals);
	}

	public static function clearInvalids()
	{
		clearInvalidFrom(imagesToPrepare, 'images', '.png', IMAGE); // leaving this as is
		// clearInvalidFrom(imagesToPrepare, 'images', '.${Paths.IMAGE_EXT}', Paths.IMAGE_ASSETTYPE);
		clearInvalidFrom(soundsToPrepare, 'sounds', '.ogg', SOUND);
		clearInvalidFrom(musicToPrepare, 'music', ' .ogg', SOUND);
		clearInvalidFrom(songsToPrepare, 'songs', '.ogg', SOUND, 'songs');

		for (arr in [imagesToPrepare, soundsToPrepare, musicToPrepare, songsToPrepare])
			while (arr.contains(null))
				arr.remove(null);
	}

	static function clearInvalidFrom(arr:Array<String>, prefix:String, ext:String, type:AssetType, ?library:String = null)
	{
		for (i in 0...arr.length)
		{
			var folder:String = arr[i];
			if (folder.trim().endsWith('/'))
			{
				for (subfolder in Mods.directoriesWithFile(Paths.getSharedPath(), '$prefix/$folder'))
					for (file in Paths.readDirectory(subfolder))
						if (file.endsWith(ext))
							arr.push(folder + file.substr(0, file.length - ext.length));

				// trace('Folder detected! ' + folder);
			}
		}

		var i:Int = 0;
		while (i < arr.length)
		{
			var member:String = arr[i];
			var myKey = '$prefix/$member$ext';
			if (library == 'songs')
				myKey = '$member$ext';

			// trace('attempting on $prefix: $myKey');
			var doTrace:Bool = false;
			if (member.endsWith('/') || (!Paths.fileExists(myKey, type, false, library) && (doTrace = true)))
			{
				arr.remove(member);
				if (doTrace)
					trace('Removed invalid $prefix: $member');
			}
			else
				i++;
		}
	}

	public static function startThreads()
	{
		loadMax = imagesToPrepare.length + soundsToPrepare.length + musicToPrepare.length + songsToPrepare.length;
		loaded = 0;

		// then start threads
		for (sound in soundsToPrepare)
			initThread(() -> Paths.sound(sound), 'sound $sound');
		for (music in musicToPrepare)
			initThread(() -> Paths.music(music), 'music $music');
		for (song in songsToPrepare)
			initThread(() -> Paths.returnSound(null, song, 'songs'), 'song $song');

		// for images, they get to have their own thread
		for (image in imagesToPrepare)
		{
			#if (target.threaded)
			Thread.create(() -> {
			#end
				#if (target.threaded)
				mutex.acquire();
				#end
				try
				{
					var bitmap:BitmapData = null;
					var file:String = null;

					#if MODS_ALLOWED
					file = Paths.modsImages(image);
					if (Paths.currentTrackedAssets.exists(file))
					{
						#if (target.threaded)
						mutex.release();
						#end
						loaded++;
						return;
					}
					else if (FileSystem.exists(file))
						bitmap = BitmapData.fromFile(file);
					else
					#end
					{
						file = Paths.getPath('images/$image.${Paths.GPU_IMAGE_EXT}', Paths.getImageAssetType(Paths.GPU_IMAGE_EXT));
						if (Paths.currentTrackedAssets.exists(file))
						{
							#if (target.threaded)
							mutex.release();
							#end
							loaded++;
							return;
						}
						else if (OpenFlAssets.exists(file, Paths.getImageAssetType(Paths.GPU_IMAGE_EXT)))
							bitmap = OpenFlAssets.getBitmapData(file);
						else
						{
							file = Paths.getPath('images/$image.${Paths.IMAGE_EXT}', Paths.getImageAssetType(Paths.IMAGE_EXT));
							if (Paths.currentTrackedAssets.exists(file))
							{
								#if (target.threaded)
								mutex.release();
								#end
								loaded++;
								return;
							}
							else if (OpenFlAssets.exists(file, Paths.getImageAssetType(Paths.IMAGE_EXT)))
								bitmap = OpenFlAssets.getBitmapData(file);
							else
							{
								trace('no such image $image exists');
								#if (target.threaded)
								mutex.release();
								#end
								loaded++;
								return;
							}
						}
					}
					#if (target.threaded)
					mutex.release();
					#end

					if (bitmap != null)
						requestedBitmaps.set(file, bitmap);
					else
						trace('oh no the image is null NOOOO ($image)');
				}
				catch (e:Dynamic)
				{
					#if (target.threaded)
					mutex.release();
					#end
					trace('ERROR! fail on preloading image $image');
				}
				loaded++;
			#if (target.threaded)
			});
			#end
		}
	}

	static function initThread(func:Void->Dynamic, traceData:String)
	{
		#if (target.threaded)
		Thread.create(() -> {
		#end
			#if (target.threaded)
			mutex.acquire();
			#end
			try
			{
				var ret:Dynamic = func();
				#if (target.threaded)
				mutex.release();
				#end

				if (ret != null)
					trace('finished preloading $traceData');
				else
					trace('ERROR! fail on preloading $traceData');
			}
			catch (e:Dynamic)
			{
				#if (target.threaded)
				mutex.release();
				#end
				trace('ERROR! fail on preloading $traceData');
			}
			loaded++;
			#if (target.threaded)
			mutex.release();
			#end
		#if (target.threaded)
		});
		#end
	}

	inline private static function preloadCharacter(char:String, ?prefixVocals:String)
	{
		try
		{
			var path:String = Paths.getPath('characters/$char.json', TEXT, null, true);
			#if MODS_ALLOWED
			var character:Dynamic = haxe.Json.parse(File.getContent(path));
			#else
			var character:Dynamic = haxe.Json.parse(Assets.getText(path));
			#end

			imagesToPrepare.push(character.image);
			if (prefixVocals != null && character.vocals_file != null)
			{
				songsToPrepare.push(prefixVocals + "-" + character.vocals_file);
				if (char == PlayState.SONG.player1)
					dontPreloadDefaultVoices = true;
			}
		}
		catch (e:Dynamic)
		{
		}
	}
}
