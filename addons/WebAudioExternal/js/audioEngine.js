function AudioEngine() {
  this.enable = false;
  this.files = {};
  this.autoPlayPool = [];
  this.loadedFiles = [];
  this.audioKeyPlaying = [];
  this.audiosTypes = ["mp3"];

	this.propTopropEngine = {
		"pan":"stereo",
		"panner":"pannerAttr",
		"pitch":"rate"
	}
	
	this.valueTovalueEngine = {
		"volume":"processVolume"
	}
}

AudioEngine.prototype.initAudios = function (audio_files, path, config) {
  var self = this;
  
  // Unload any existing Howl instances to prevent memory leaks and overlapping loops
  for (let key in this.files) {
    if (this.files[key]) {
      try {
        this.files[key].unload();
      } catch (e) {
        console.error("Error unloading sound: " + key, e);
      }
    }
  }
  this.files = {};
  this.loadedFiles = [];
  this.audioKeyPlaying = [];
  this.autoPlayPool = [];

  for (let keyfile in audio_files) {
    let filename = audio_files[keyfile];
    let _path_audio = path + "/" + filename;
    if (filename.indexOf('.') === -1) {
      _path_audio += "." + this.audiosTypes[0];
    }
    
    let objectHowl = {
      src: [_path_audio],
      preload: true,
      autoUnlock: true,
      autoSuspend: false,
      xhrWithCredentials: false,
      html5: false,
      mute: true,
      onplayerror: function (e) {
        let _audio = this;
        console.log("[onplayerror] " + e);
        this.once("unlock", function () {
          _audio.seek();
          _audio.play();
        });
      },
      unload: function () {
        console.log("[unload] " + this._src);
        this.load();
      },
      onloaderror: function () {
        console.warn("[onloaderror] Failed to load audio source: " + this._src);
        self.loadedFile(this._src);
      },
      onload: function () {
        self.loadedFile(this._src);
        this.mute(false);
      },
    };
    objectHowl = Object.assign(objectHowl, config);

    Howler.autoUnlock = true;
    Howler.autoSuspend = false;
    //Howler.html5PoolSize = 50;
	console.log(objectHowl);

    this.files[audio_files[keyfile]] = new Howl(objectHowl);
  }
};

AudioEngine.prototype.loadedFileDone = function () {
  if (this.autoPlayPool.length>0) {
    this.autoPlayPool.forEach((audio) => {
      this.playAudio(audio);
    });
  }
};

AudioEngine.prototype.loadedFile = function (src) {
  if (this.loadedFiles.indexOf(src) == -1) {
    this.loadedFiles.push(src);
  }
  if (this.statusFilesLoadAudio() == 1) {
    this.loadedFileDone();
  }
};

AudioEngine.prototype.getListenerPosition = function(){
	console.log("getListenerPosition "+Howler.pos())
	return Howler.pos().toString()
}

AudioEngine.prototype.getAudioSourcePosition = function(audioNameString,audioID){
	let audioResponse = this.files[audioNameString];
	return audioResponse._pos.toString();
}

AudioEngine.prototype.setSourcePosition =  function(new_pos, audioID,audioNameString){
	let audioResponse = this.files[audioNameString]

	audioResponse.pos(Math.round(new_pos[0]),Math.round(new_pos[1]),Math.round(new_pos[2]),audioID)
	audioResponse._pos = new_pos
}
AudioEngine.prototype.setSourceOrientation =  function(new_pos, audioID,audioNameString){
	let audioResponse = this.files[audioNameString]
	
	audioResponse.orientation(new_pos[0],new_pos[1],new_pos[2])
}

AudioEngine.prototype.updateListenerPosition = function(new_pos){
	Howler.pos(...new_pos)
}

AudioEngine.prototype.updateListenerOrientation = function(new_orientatio){
	console.log("update listener orient "+new_orientatio);
	Howler.orientation(...new_orientatio)
}

AudioEngine.prototype.statusFilesLoadAudio = function () {
  var count_audio = Object.keys(this.files).length;
  if (count_audio == 0 || this.loadedFiles.length == 0) return 0;
  else {
    return this.loadedFiles.length / count_audio;
  }
};

AudioEngine.prototype.statusAudioPlaying = function (_key) {
  return this.audioKeyPlaying.indexOf(_key);
};

AudioEngine.prototype.playAudio = function (audioName, effectsToApply = [],_id=0) {
  let audioNameString = audioName;
  if (this.statusFilesLoadAudio() < 1){
    this.autoPlayPool.push(audioName);
    return 0;
  }

  if (typeof audioNameString == "object") audioNameString = audioName.audio;
  let audioResponse = this.files[audioNameString];
  this.audioKeyPlaying.push(audioNameString);

  //aplica os efeitos
  if (effectsToApply.length > 0) {
	console.log("play aplica efeitos") 
     this.processEffects(audioResponse,effectsToApply);
  }
  let id = audioResponse.play();
  audioResponse.once("end", () => {
    if(!audioResponse.loop()){
      this.removeKeyPlaying(audioNameString)
    }
  }, id);
  return id;
};
AudioEngine.prototype.updateConfigAudio = function (_config,_audios) {
	_audios.forEach(_audio=>{
  		let audioResponse = this.files[_audio];
		this.processEffects(audioResponse,_config)
	});
};

AudioEngine.prototype.processEffects = function (audioResponse,effectsToApply){
	//propTopropEngine
	effectsToApply.forEach((item) => {
      if (typeof item == "string") {
		// aciona um método diretamente, sem parametro
		var _key = item;
		if (item in this.propTopropEngine){
			_key = this.propTopropEngine[item];
		}
        audioResponse[_key]();
      } else {
		var _key = [item.name];
		var _value = item.params;
		
		if( _key[0] in this.propTopropEngine ){
			_key.push(this.propTopropEngine[_key[0]])
		}
		
		if( _key[0] in this.valueTovalueEngine && this.valueTovalueEngine[_key[0]] in this ){
			_value = [this[this.valueTovalueEngine[_key[0]]](..._value)]
		}
		
		_key.forEach(__key=>{
			if ( audioResponse.hasOwnProperty(__key) && item.params.length==1){
				console.log("propriedade "+__key+" "+_value);
				audioResponse[__key] = _value;
			}else if (__key in audioResponse && typeof(audioResponse[__key])=='function') {
				console.log("metodo "+__key+" ("+JSON.stringify(..._value)+")" );
				audioResponse[__key].call(audioResponse,..._value);
			}
		})
	}

    });
}

// Howler manage volume like 0-1, here convert min and max to pattern Howler
AudioEngine.prototype.processVolume = function (volume, min=-80, max = 0){
  if (volume <= -79) return 0;
  var new_volume = Math.pow(10, volume / 20);
  new_volume = Math.max(0, Math.min(1, new_volume));
  return Math.round(new_volume * 100) / 100;
}

AudioEngine.prototype.removeKeyPlaying = function (key){
  if (this.audioKeyPlaying.indexOf(key) > -1) {
    this.audioKeyPlaying.splice(
      this.audioKeyPlaying.indexOf(key),
      1
    );
  }
}

AudioEngine.prototype.pauseAudio = function (audioName){
	this.files[audioName].pause();
	this.removeKeyPlaying(audioName);
}

AudioEngine.prototype.stopAudio = function (audioName = "") {
  if (audioName == "") {
    if (this.audioKeyPlaying.length > 0) {
      console.log("stop audio from audioapi");
      this.audioKeyPlaying.foreach((key) => {
        this.files[key].stop();
      });
    }
  } else {
    let audioNameString = audioName;
    if (typeof audioNameString == "object") audioNameString = audioName.audio;
    this.files[audioNameString].stop();
    this.removeKeyPlaying(audioNameString);
  }
};
