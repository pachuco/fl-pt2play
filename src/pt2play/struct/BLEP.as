package pt2play.struct 
{

import pt2play.C;

public class BLEP 
{
    public var
        index:int,              //int32_t
        samplesLeft:int,        //int32_t
        buffer:Vector.<Number>, //float[RNS + 1]
        lastValue:Number;       //float
    
    
    public function BLEP() 
    {
        buffer = new Vector.<Number>(C.RNS + 1);
        //C inits floats to 0, AS3 inits to NaN
        for (var i:int = 0; i < buffer.length; i++) buffer[i] = 0.0;
        
        lastValue = 0;
    }
    
}

}