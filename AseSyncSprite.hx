package ;
import AseSync.*;
import haxe.io.Path;
import yy.*;
import haxe.macro.Expr.Var;
import sys.FileSystem;
import sys.io.File;
import tools.FileTools;
import tools.MathTools;
using StringTools;

/**
 * ...
 * @author YellowAfterlife
 */
class AseSyncSprite {
	static function createGUID():String {
		var result = "";
		for (j in 0 ... 32) {
			if (j == 8 || j == 12 || j == 16 || j == 20) {
				result += "-";
			}
			if (j == 12) {
				result += "4";
			}
			else if (j == 16) {
				result += "89ab".charAt(Std.random(4));
			}
			else {
				result += "0123456789abcdef".charAt(Std.random(16));
			}
		}
		return result;
	}
	
	public static function sync(asePath:String) {
		var fileName = (new Path(asePath)).file;
		
		if (fileNameIsInIgnoreList(fileName)) return;

		var name = gmSpritePrefix + fileName;
		var yyDir = '$projectDir/sprites/$name';
		var yyPath = '$yyDir/$name.yy';
		var yyRel = 'sprites/$name/$name.yy';
		var spr:YySprite;
		var save = false;
		if (FileSystem.exists(yyPath)) {
			Sys.println('Syncing existing sprite: $name ($asePath)...');
			spr = YyJson.parse(File.getContent(yyPath));
		} else {
			if (updateOnly) {
				Sys.println('Not creating new GM Asset for this sprite: ($name), due to updateOnly flag being set to true');
				return;
			}
			
			Sys.println('Creating new GM Asset for sprite: $name ($asePath)...');
			save = true;
			spr = YyJson.parse(baseSpriteText);
			spr.frames = [];
			spr.sequence.tracks[0].keyframes.Keyframes = [];
			spr.name = name;
			
			if (projectData == null) projectData = YyJson.parse(File.getContent(projectPath));
			
			var aseNorm = Path.normalize(asePath);
			if (StringTools.startsWith(aseNorm, watchDir + "/")) { // create YYP folder chain
				aseNorm = aseNorm.substring(watchDir.length + 1);
				var dir = Path.directory(aseNorm);
				if (dir != "") {
					if (prefix != "") dir = '$prefix/$dir';
				} else dir = prefix;
				if (dir != "") {
					var pre = "folders";
					var folderPath:String = pre + ".yy";
					var parts = dir.split("/");
					for (part in parts) {
						pre += '/$part';
						folderPath = '$pre.yy';
						var found = false;
						for (folder in projectData.Folders) {
							if (folder.folderPath == folderPath) {
								found = true;
								break;
							}
						}
						if (!found) {
							projectData.Folders.push({
								folderPath: folderPath,
								order: maxOrder,
								resourceVersion: "1.0",
								name: part,
								tags: [],
								resourceType: "GMFolder",
							});
						}
						//trace(part, pre);
					}
					spr.parent.name = parts[parts.length - 1];
					spr.parent.path = folderPath;
				} // dir != ""
				if (!FileSystem.exists(yyDir)) FileSystem.createDirectory(yyDir);
			}
			
			projectData.resources.push({
				id: { name: name, path: 'sprites/$name/$name.yy' },
				order: maxOrder,
			});
		}
		
		var tmp = 'tmp/$name';
		if (!FileSystem.exists(tmp)) FileSystem.createDirectory(tmp);
		Sys.command(asepritePath, [
			"-b",
			"--data", '$tmp/data.json',
			asePath,
			"--save-as", '$tmp/0.png',
		]);
		
		var aseData:AseData = {
			var _storeKeys = YyJsonParser.storeKeys;
			YyJsonParser.storeKeys = true;
			var _aseData = YyJsonParser.parse(File.getContent('$tmp/data.json'));
			YyJsonParser.storeKeys = _storeKeys;
			_aseData;
		};
		var keys:Array<String> = cast aseData.frames["__keys__"];
		var aseSize = aseData.frames[keys[0]].sourceSize;
		var aseWidth = aseSize.w;
		var aseHeight = aseSize.h;
		
		var keyframes = spr.sequence.tracks[0].keyframes.Keyframes;
		var framesPerFrame = spr.sequence.playbackSpeedType == 1;
		
		if (spr.width != aseWidth || spr.height != aseHeight) {
			spr.width = aseWidth;
			spr.height = aseHeight;
			if (spr.origin < 9) {
				spr.sequence.xorigin = ((spr.origin % 3) * aseWidth) >> 1;
				spr.sequence.yorigin = (Std.int(spr.origin / 3) * aseHeight) >> 1;
			}
			save = true;
		}
		
		var msPerFrame = 0.;
		if (spr.sequence.playbackSpeedType == 0) {
			var frameTimings = [];
			for (i => k in keys) {
				var dur = aseData.frames[k].duration;
				if (frameTimings.indexOf(dur) < 0) frameTimings.push(dur);
			}
			
			var frameTime:Float;
			if (false) { // sprite editor shows overly long frames weirdly, so better not
				var gcd = frameTimings[0];
				for (i in 1 ... frameTimings.length) gcd = MathTools.gcd(gcd, frameTimings[i]);
				frameTime = gcd;
			} else {
				var minTime = frameTimings[0];
				for (i in 1 ... frameTimings.length) {
					var ft = frameTimings[i];
					if (ft < minTime) minTime = ft;
				}
				frameTime = minTime;
			}
			
			var fps = MathTools.roundIfCloseToEps(1000 / frameTime);
			{ // if FPS has too many digits after period, use 10fps for precision instead
				var fpsStr = Std.string(fps);
				var dotAt = fpsStr.indexOf(".");
				if (dotAt >= 0 && dotAt < fpsStr.length - 4) fps = 10;
			}
			msPerFrame = 1000 / fps;
			spr.sequence.playbackSpeed = fps;
			Sys.println('[$name] ref frame time: $frameTime, FPS: $fps');
		}
		
		var time = 0.;
		for (i => key in keys) {
			var af = aseData.frames[key];
			var dur = 1.;
			if (msPerFrame != 0) {
				dur = MathTools.roundIfCloseToEps(af.duration / msPerFrame);
			}
			var sf = spr.frames[i];
			var kf = keyframes[i];
			if (sf == null) {
				sf = YyJson.parse(baseSpriteFrameText);
				var guid = createGUID();
				sf.parent = { name: name, path: yyRel };
				var img = sf.images[0];
				img.FrameId.name = guid;
				img.FrameId.path = yyRel;
				img.LayerId.name = spr.layers[0].name;
				img.LayerId.path = yyRel;
				sf.parent.name = name;
				sf.parent.path = yyRel;
				sf.name = guid;
				sf.compositeImage.FrameId.name = guid;
				sf.compositeImage.FrameId.path = yyRel;
				spr.frames.push(sf);
				//
				kf = YyJson.parse(baseSpriteKeyFrameText);
				kf.id = createGUID();
				kf.Key = time;
				kf.Length = dur;
				kf.Channels["0"].Id.name = guid;
				kf.Channels["0"].Id.path = yyRel;
				keyframes.push(kf);
				save = true;
			} else if (kf.Key != time || kf.Length != dur) {
				kf.Key = time;
				kf.Length = dur;
				save = true;
			}
			var src = '$tmp/$i.png';
			var dst = yyDir + "/" + sf.compositeImage.FrameId.name + ".png";
			if (!FileTools.compare(src, dst)) {
				Sys.println('Copying $src to $dst...');
				File.copy(src, dst);
			}
			time += dur;
		}
		if (spr.sequence.length != time) {
			spr.sequence.length = time;
			save = true;
		}
		
		// remove extra frames
		var i = spr.frames.length;
		while (--i >= keys.length) {
			var guid = spr.frames[i].compositeImage.FrameId.name;
			FileSystem.deleteFile('$yyDir/$guid.png');
			spr.frames.pop();
			keyframes.pop();
			save = true;
		}
		
		if (save) {
			File.saveContent(yyPath, YyJson.stringify(spr));
		}
	}

	static function fileNameIsInIgnoreList(fileName:String):Bool {
		for (ignoreString in ignoreStrings) {
			if (StringTools.contains(fileName, ignoreString)) {
				Sys.println('FileName: ($fileName) was ignored due to including: ($ignoreString)');
				return true;
			}
		}

		return false;
	}
	
}