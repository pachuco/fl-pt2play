package
{
import flash.utils.ByteArray;
import flash.display.Sprite;
import flash.events.Event;
import pt2play.PT2Player;
import debug.T;
import com.sociodox.theminer.*;

/**
 * ...
 * @author 
 */
public class Main extends Sprite 
{
    
    [Embed(source="mus/BrianTheLion01.mod", mimeType="application/octet-stream")]
    private var Song:Class;
    private var player:PT2Player;
    
    //private var miner:TheMiner;
    
    public function Main() 
    {
        if (stage) init();
        else addEventListener(Event.ADDED_TO_STAGE, init);
    }
    
    private function init(e:Event = null):void 
    {
        removeEventListener(Event.ADDED_TO_STAGE, init);
        // entry point
        //miner = new TheMiner();
        //this.addChild(miner);
        
        //new T(this.stage, 0x000000);
        
        player = new PT2Player();
        //Leave mode 0(CIA) for now. Vblank is trouble with all but a few songs
        player.pt2play_PlaySong(new Song() as ByteArray, 0);
    }
    
}

}