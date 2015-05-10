package example_urlplayer
{
	import flash.display.Sprite;
	import flash.events.*;
    import flash.net.*;
    
    import pt2play.PT2Player;
    
    
    /**
     * ...
     * @author 
     */
    public class Main extends Sprite 
    {
        private var replayer:PT2Player;
        private var qs:QueryString;
        
        private var ef:ErrorField;
        
        private var p_song:String;
        private var p_stereo:uint;
        private var p_vblank:uint;
        
        public function Main():void 
        {
            if (stage) init();
            else addEventListener(Event.ADDED_TO_STAGE, init);
        }
        
        private function init(e:Event = null):void 
        {
            removeEventListener(Event.ADDED_TO_STAGE, init);
            // entry point
            ef = new ErrorField(this, 20, 40, 750, 0x000000);
            try {
                qs = new QueryString("");
                p_song = qs.parameters.song as String;
                p_stereo = qs.parameters.stereo == null ? 50 : uint(qs.parameters.stereo);
                p_vblank = qs.parameters.vblank == null ? 0 : uint(qs.parameters.vblank);
                
                if (p_song == null || p_song == "") {
                    ef.appendError("Usage example:");
                    ef.appendError(SWFName(this) + "?song=corruption.mod&stereo=100&vblank=1");
                    ef.appendError("song -- filename of song on the server");
                    ef.appendError("stereo -- separation in percent, 0 - 100");
                    ef.appendError("vblank -- breaks tunes, 0 - 1");
                    return;
                }
                replayer = new PT2Player();
                loadSongFromURL(p_song);
                ef.appendError("songurl: " + p_song);
            }catch (e:Error) {
                ef.appendError(e.message);
            }
        }
        
        public function loadSongFromURL(url:String):void
        {
            var loader:URLLoader;
            
            var evtSongLoadError:Function = function(evt:IOErrorEvent):void
            {
                ef.appendError("error loading song");
                loader = null;
            }
            
            var evtSongLoadSuccess:Function = function(evt:Event):void
            {
                replayer.pt2play_SetStereoSep(p_stereo);
                replayer.pt2play_PlaySong(loader.data, p_vblank);
                loader = null;
            }
            
            
            var request:URLRequest;
            
            request = new URLRequest(url);
            loader = new URLLoader();
            loader.dataFormat = URLLoaderDataFormat.BINARY;
            try {
                loader.load(request);
            } catch (e:Error) {
                ef.appendError(e.message);
            }
            loader.addEventListener(IOErrorEvent.IO_ERROR, evtSongLoadError);
            loader.addEventListener(Event.COMPLETE, evtSongLoadSuccess);
        }
        
        private function SWFName(symbol:Sprite):String
        {
            var swfName:String;
            swfName = symbol.loaderInfo.url;
            swfName = swfName.slice(swfName.lastIndexOf("/") + 1); // Extract the filename from the url
            var indexCrap:uint = swfName.indexOf("?");
            if(indexCrap >= 0) {
                swfName = swfName.slice(0, indexCrap); // Extract the filename from the url
            }
            swfName = new URLVariables("path=" + swfName).path; // this is a hack to decode URL-encoded values
            return swfName;
        }
    }
    
}