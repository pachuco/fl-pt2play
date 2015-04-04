package
{
import flash.utils.ByteArray;
import flash.display.Sprite;
import flash.events.Event;
import pt2play.PT2Player;

/**
 * ...
 * @author 
 */
public class Main extends Sprite 
{
    
    [Embed(source="4travis3.mod", mimeType="application/octet-stream")]
    private var Song:Class;
    private var player:PT2Player;
    
    
    public function Main() 
    {
        if (stage) init();
        else addEventListener(Event.ADDED_TO_STAGE, init);
    }
    
    private function init(e:Event = null):void 
    {
        removeEventListener(Event.ADDED_TO_STAGE, init);
        // entry point
        player = new PT2Player();
        //Leave mode 0(CIA) for now. Vblank is trouble with all but a few songs
        player.pt2play_PlaySong(new Song() as ByteArray, 0);
    }
    
}

}