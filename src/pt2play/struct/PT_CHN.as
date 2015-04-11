package pt2play.struct 
{

import pt2play.C;

public class PT_CHN 
{
    public var
        n_note:int,                 //int16_t     
        n_cmd:uint,                 //uint16_t    
        n_index:int,                //int8_t      
        n_start:uint,               //*int8_t  
        n_wavestart:uint,           //*int8_t  
        n_loopstart:uint,           //*int8_t  
        n_volume:int,               //int8_t  
        n_toneportdirec:int,        //int8_t  
        n_vibratopos:int,           //int8_t  
        n_tremolopos:int,           //int8_t  
        n_pattpos:int,              //int8_t  
        n_loopcount:int,            //int8_t  
        n_wavecontrol:uint,         //uint8_t 
        n_glissfunk:uint,           //uint8_t 
        n_sampleoffset:uint,        //uint8_t 
        n_toneportspeed:uint,       //uint8_t 
        n_vibratocmd:uint,          //uint8_t 
        n_tremolocmd:uint,          //uint8_t 
        n_finetune:uint,            //uint8_t 
        n_funkoffset:uint,          //uint8_t 
        n_period:int,               //int16_t 
        n_wantedperiod:int,         //int16_t 
        n_length:uint,              //uint32_t
        n_replen:uint,              //uint32_t
        n_repend:uint;              //uint32_t
       
    public function PT_CHN() 
    {  
       n_start     = C.NULL;
       n_wavestart = C.NULL;
       n_loopstart = C.NULL;
    }
    
}

}