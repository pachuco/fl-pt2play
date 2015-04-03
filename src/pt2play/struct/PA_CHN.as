package pt2play.struct 
{

import pt2play.C;

public class PA_CHN 
{
    public var
        DAT:uint,           //*int8_t
        REPDAT:uint,        //*int8_t
        TRIGGER:int,        //int8_t

        REPLEN:uint,        //uint32_t
        POS:uint,           //uint32_t
        LEN:uint,           //uint32_t

        LASTDELTA:Number,   //float
        DELTA:Number,       //float
        LASTFRAC:Number,    //float
        FRAC:Number,        //float
        VOL:Number,         //float
        PANL:Number,        //float
        PANR:Number;        //float
    
    public function PA_CHN() 
    {
        DAT = C.NULL;
        REPDAT = C.NULL;
        
        LASTDELTA = 0.0;
        DELTA = 0.0;
        LASTFRAC = 0.0;
        FRAC = 0.0;
        VOL = 0.0;
        PANL = 0.0;
        PANR = 0.0;
    }
    
}

}