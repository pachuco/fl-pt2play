package example_urlplayer  
{
    import flash.text.TextField;
    import flash.text.TextFieldAutoSize;
    import flash.display.Stage;
	import flash.events.*;
    import flash.display.DisplayObjectContainer;
    /**
     * ...
     * @author 
     */
    public class ErrorField extends TextField
    {
        
        public function ErrorField(parent:DisplayObjectContainer, x:Number, y:Number, width:Number, color:uint) 
        {
            parent.addChild(this);
            this.x = x;
            this.y = y;
            this.width = width;
            this.selectable = true;
            this.autoSize = TextFieldAutoSize.LEFT;
            this.wordWrap = true;
            this.background = true;
            this.backgroundColor = color | 0xFF000000;
            this.textColor = (~color) | 0xFF000000;
            
            if (stage) init();
            else addEventListener(Event.ADDED_TO_STAGE, init);
        }
        
        private function init(e:Event = null):void 
        {
            removeEventListener(Event.ADDED_TO_STAGE, init);
            // entry point
        }
        
        public function appendError(obj:*):void {
            var s:String = obj.toString();
            if (this.text != "") this.text += "\n";
            this.text += s;
        }
    }

}