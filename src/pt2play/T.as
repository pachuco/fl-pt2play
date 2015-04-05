package pt2play 
{

import flash.display.Sprite;
import flash.display.Stage;
import flash.text.TextField;


public class T 
{
    private static var stage:Stage;
    private static var tfield:TextField;
    private static var bgshape:Sprite;
    
    private static var buffer:Vector.<String>;
    private static var index:uint;
    private static var bufflen:uint;
    
    public function T(s:Stage, color:uint) 
    {
        stage = s;
        
        bgshape = new Sprite();
        bgshape.graphics.beginFill(color);
        bgshape.graphics.drawRect(0,0,stage.stageWidth, stage.stageHeight);
        s.addChild(bgshape);
        
        tfield = new TextField();
        tfield.multiline = true;
        tfield.selectable = true;
        tfield.wordWrap = false;
        tfield.height = s.stageHeight;
        tfield.width = s.stageWidth;
        tfield.textColor = (~color) & 0xFFFFFF;
        tfield.text = " ";
        s.addChild(tfield);
        
        bufflen = Math.floor(tfield.height / tfield.textHeight) - 1;
        buffer = new Vector.<String>(bufflen);
        /*
        for (var i:int = 0; i < bufflen; i++) 
        {
            buffer[i] = " ";
        }
        */
        index = 0;
    }
    
    public static function race(obj:*):void
    {
        var str:String = obj.toString();
        /*
        if (obj is Object)
        {
            str = obj.toString;
        }else {
            str = obj;
        }
        */
        tfield.text = "";
        buffer[index] = str;
        for (var i:int = 0; i < bufflen; i++)
        {
            var temp:String = buffer[(index + i+1) % bufflen];
            if(temp != null) tfield.appendText(temp + "\n");
        }
        trace(index);
        ++index;
        index %= bufflen;
    }
}

}